# frozen_string_literal: true

require_relative "../../paths"
require_relative "../../config"
require_relative "../../target"
require_relative "../../gc_tuning"
require_relative "../command"
require_relative "../options"
require_relative "../refusals"
require_relative "../runner"
require_relative "gems"

module Zr
  module CLI
    module Commands
      # `run` and `build`: compile a program, then run it, or keep the
      # binary, the WASI module or the object.
      #
      # A compile command also holds what a process that serves builds
      # needs: the binary that a `zr run` found in the run cache
      # (`kept!`), and the block that takes a binary in place of running it
      # (`served!`).
      #
      # In `Commands`, `Cache` names the command `cache`: the caches are
      # `Zr::Cache`.
      class Compile < Command
        def reads_help? = true

        # `run` or `build`, and its arguments.
        def run(argv)
          opts = Options.parse(name, argv)
          Refusals.pinned!
          input = opts[:input]
          abort "zr: no such file: #{input}" unless File.file?(input)
          gems = Options.gem_set(opts)

          target = Options.target_for(opts[:triple], opts[:emit], name)
          emit = opts[:emit] || ("wasm" if target.outputs == [:wasm])
          usage_error("--link applies only to a native binary") if emit && !opts[:link].empty?
          Refusals.refuse(input, name, emit, target, chosen: !opts[:triple].nil?)
          wasmtime! if name == "run" && emit == "wasm"

          Paths.root = opts[:root]
          link = Config.current.link + opts[:link]
          cache = @missed || kept_run(input, target, link, opts[:args], gems) if name == "run" && emit.nil?
          require_relative "../../runtime"
          require_relative "../../native/build"
          # Under ruby, lib/zr/prism.rb turns the parse cache on. A compiled
          # compiler turns it on here. A program that calls eval includes the
          # same files but never comes here, so it never writes to the cache.
          require_relative "../../cache/parse" unless HOSTED
          if name == "run" && emit.nil? && Zr::Cache::Run.wanted?
            cache ||= Zr::Cache::Run.new(input, target: target, digest: Runtime.for(target).digest, link: link, gems: gems)
          end
          # Only `zr build` notes a require that will raise LoadError when it
          # runs; `run` and `diff` print the program's output alone.
          gate = opts[:runtime_require] ? false : (name == "build" ? :warn : true)
          program = lower(input, target, assemble: emit.nil?, gem_set: gems, gate: gate)
          status = Paths.tmpdir("zr-build-") do |work|
            out = name == "run" ? File.join(work, "program") : File.expand_path(opts[:output])
            case emit
            when "obj" then object(program, out)
            when "wasm" then wasm(program, out, opts[:args])
            else native(program, out, work, opts[:args], link: link, cache: cache)
            end
          end
          print Gems.table(program.gems) if opts[:print_gems]
          require_relative "../../cache/janitor"
          Zr::Cache::Janitor.trim
          Runner.exit_as(status) if status.is_a?(Process::Status)
        end

        # In a build that the server runs (lib/zr/server.rb), `zr run` gives
        # its binary to the block, in place of running it: the path, the
        # program's arguments, and whether the path is in the build directory,
        # which goes away when the build ends.
        def served!(&back)
          @served = back
        end

        # A `zr run` whose binary is in the run cache: execs the binary now,
        # before zr looks for a compiled compiler or starts again with the
        # collector limits (40 ms each). This process then is the program, so
        # its status and signals are the program's own. Does nothing for any
        # other command, for a `zr run` that needs a build, and in the second
        # start (whose first start already looked).
        def kept!(argv)
          return unless argv.first == "run" && !ENV.key?(GcTuning::ADDED) && !Host.compiled?

          require_relative "../../cache/run"
          return unless Zr::Cache::Run.wanted?

          opts = Options.parse("run", argv.drop(1))
          return if opts[:emit] || opts[:triple] || Refusals.host_refusal || !File.file?(opts[:input])

          target = Target.default
          return unless target.runs_here? && target.refusal(nil).nil?

          Paths.root = opts[:root]
          # A set that does not resolve goes on to the build, which says why.
          gems = kept_gems(opts) or return
          digest = RuntimeSources.for(target).runtime_digest or return
          cache = Zr::Cache::Run.new(opts[:input], target: target, digest: digest, link: Config.current.link + opts[:link], gems: gems)
          kept = cache.hit
          exec(GcTuning.program_env, [kept, kept], *opts[:args]) if kept
          # The build keeps its binary here, with no second digest.
          @missed = cache
        end

        # A binary's functions are assembled as they are lowered, so the IR of
        # a large program is never all in memory at once (`Native::Build.lower`).
        # Returns a `Zr::Program`.
        def lower(input, target, assemble: false, gem_set: nil, gate: false)
          source = File.read(input)
          return Program.build(source, input, target: target, gem_set: gem_set, gate: gate) unless assemble

          Native::Build.lower(source, input, target: target, sources: name == "run", gem_set: gem_set, gate: gate)
        rescue Refused => e
          warn Refusals.refusal_report(e)
          exit REFUSED
        rescue Backend::Refused => e
          # A backend refuses code that the front end let through: a limit or
          # a defect in zr, not a form of Ruby that the program must avoid.
          abort "zr: zr cannot compile this program: #{e.message}. This is a limit or a defect in zr. " \
                "Report it at #{ISSUES_URL}."
        rescue SyntaxError => e
          # For a program that does not parse, ruby prints a report and exits
          # 1. The binary does the same, with ruby's own report. In ruby, a
          # required file that does not parse raises when the require runs.
          # zr does not support this, so it refuses.
          report = Refusals.syntax_report(input)
          unless report
            warn "zr: a required file does not parse: #{e.message.lines.first.chomp}"
            exit REFUSED
          end
          warn "zr: warning: #{input} does not parse. The output prints ruby's syntax error and exits with status 1" if name == "build"
          Program.build("$stderr.write(#{report.inspect})\nexit 1\n", input, target: target)
        end

        private

        # `zr run --emit wasm` runs the module with wasmtime. Without it, stop
        # before the build.
        def wasmtime!
          require_relative "../../doctor"
          return if Zr::Doctor.which("wasmtime")

          abort "zr: zr run --emit wasm needs wasmtime, and it is not on the PATH. Install it from https://wasmtime.dev, " \
                "or use 'zr build --emit wasm' to write the module only."
        end

        def object(program, out)
          why = program.write_object(out)
          abort "zr: #{why}" if why
          nil
        end

        def wasm(program, out, rest)
          why = program.write_wasm(out)
          abort "zr: #{why}" if why
          return nil unless name == "run"

          # The module can see the working directory, as a ruby program can.
          # `system`, not `exec`, so that the build directory goes away after
          # the run, as for a binary.
          interrupt = Signal.trap("INT") { nil }
          system("wasmtime", "run", "--dir", ".", out, *rest)
          Signal.trap("INT", interrupt)
          $?
        end

        def native(program, out, work, rest, link: [], cache: nil)
          why = program.write_binary(out, work: work, link: link)
          abort "zr: #{why}" if why
          return unless name == "run"

          kept = cache&.keep(out, program, work)
          return @served.call(kept || out, rest, kept.nil?) if @served

          Runner.run_binary(out, rest)
        end

        # The GemSet of a `zr run` before the build, or nil when it does not
        # resolve.
        def kept_gems(opts)
          require_relative "../../gem_set"
          GemSet.resolve(opts[:gems], gemfile: opts[:gemfile])
        rescue GemSet::Unresolved
          nil
        end

        # A program that ran before with the same sources runs from the run
        # cache, and zr exits as it does. This loads only the digests, not the
        # compiler. Returns the cache for the build otherwise, or nil when zr
        # needs a build to know the runtime's digest.
        def kept_run(input, target, link, args, gems)
          require_relative "../../cache/run"
          return nil unless Zr::Cache::Run.wanted?

          digest = RuntimeSources.for(target).runtime_digest or return nil
          cache = Zr::Cache::Run.new(input, target: target, digest: digest, link: link, gems: gems)
          kept = cache.hit
          Runner.exit_as(Runner.run_binary(kept, args)) if kept
          cache
        end
      end
    end
  end
end
