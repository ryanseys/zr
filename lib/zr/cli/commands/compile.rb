# frozen_string_literal: true

require_relative "../../error"
require_relative "../../paths"
require_relative "../../config"
require_relative "../../target"
require_relative "../../gc_tuning"
require_relative "../command"
require_relative "../options"
require_relative "../refusals"
require_relative "../runner"
require_relative "../ruby_options"
require_relative "version"
require_relative "gems"

module Zr
  module CLI
    module Commands
      # `run` and `build`: compile a program, then run it, or keep the
      # binary, the WASI module or the object.
      #
      # A compile command also holds the binary that a `zr run` found in
      # the run cache (`kept!`).
      #
      # In `Commands`, `Cache` names the command `cache`: the caches are
      # `Zr::Cache`.
      class Compile < Command
        # @rbs @missed: Zr::Cache::Run?
        # @rbs @exec: String?
        # @rbs @options: RubyOptions?
        # @rbs @given: [String, String]?

        #: () -> bool
        def reads_help? = true

        # `run` or `build`, and its arguments. The script's shebang line can
        # give ruby's switches, as for ruby (`RubyOptions#shebang!`).
        #: (Array[String] argv) -> void
        def run(argv)
          opts = Options.parse(name, argv)
          Refusals.pinned!
          input = opts[:input]
          Errors.file!(input)
          source = File.read(input)
          compile(opts, source, input, RubyOptions.new.tap { |options| options.shebang!(source) }.switches)
        end

        # `zr` as a ruby (`CLI.start`): runs the program of -e, of a script
        # or of standard input, with ruby's switches, as `ruby` would. What
        # acts before the build is done here: -v, -C, -S, -x, -c and --dump.
        # Raises RubyOptions::Invalid for a command line that ruby rejects.
        #: (Array[String] argv) -> void
        def ruby(argv)
          options = @options || RubyOptions.parse(argv)
          return CLI::Help.show(long: options.long_help?) if options.help?

          options.warnings.each { |line| warn line }
          Refusals.pinned!
          if (why = options.refused)
            warn "zr: #{why}"
            exit REFUSED
          end
          # -v gives ruby's description, as ruby does; --version gives zr's,
          # except when zr runs as `ruby`.
          puts Zr.ruby_description(Target.default.ruby_platform) if options.version || (options.version_only && as_ruby?)
          puts Version::LINE if options.version_only && !as_ruby?
          puts RUBY_COPYRIGHT if options.copyright
          # The program replaces this process, which writes its lines first.
          $stdout.flush
          return unless options.runs?($stdin.tty?)

          source, file = @given || given(options)
          return dump(source, file, options) if options.dumps?

          opts = Options.parse("run", [*options.zr, "--", file, *options.args])
          compile(opts, source, file, options.switches)
        end

        # The program's text and its file name for ruby mode: -e's code
        # (file "-e"), standard input (file "-") or the script, after -C
        # and with -S's search. Reads the switches of its shebang line, or
        # of the `#!ruby` line that -x looks for. Stops as ruby does when
        # it cannot.
        #: (RubyOptions options) -> [String, String]
        def given(options)
          options.chdirs.each do |dir|
            # -C changes the directory of zr, which the program then runs in.
            Dir.chdir(dir) # rubocop:disable ThreadSafety/DirChdir
          rescue SystemCallError
            fatal("Can't chdir to #{dir} (fatal)")
          end
          return [options.inline_source, "-e"] unless options.inline.empty?

          name = options.script
          source, file = if name.nil? || name == "-"
                           [$stdin.read.to_s, "-"]
                         else
                           path = options.search ? searched(name, verbose: options.switches.verbose == true) : name
                           [File.read(path), path]
                         end
          # A first `#!` line that does not name ruby is a launcher, and the
          # script runs as with -x, also from standard input. A `#!` with
          # nothing after it on its line is a comment, as in ruby.
          first = source.each_line.first.to_s
          options.xflag! if first.start_with?("#!") && first != "#!" && first != "#!\n" && !first.include?("ruby")
          line = options.xflag ? source.each_line.find { |text| text.start_with?("#!") && text.include?("ruby") } : source
          fatal("no Ruby script found in input (LoadError)", prefix: file) unless line
          options.shebang!(line)
          shebang_warning(source, line, file, options)
          [source, file]
        rescue SystemCallError => e
          # strerror's words, without what ruby's message adds after them.
          # A bare word that names no file reads as a mistyped command, so
          # zr says so after ruby's line.
          word = e.is_a?(Errno::ENOENT) && !as_ruby? && !options.search && !name.to_s.include?("/") && !name.to_s.end_with?(".rb")
          fatal("#{e.message.sub(/ @ .*\z/m, "")} -- #{name} (LoadError)",
                hint: ("zr: '#{name}' is not a zr command either; run 'zr help' for the commands." if word))
        end

        # load_file: a shebang line that names ruby and ends with "\r\n"
        # warns at its line, unless $VERBOSE is nil. Under -x the parse's
        # own warnings, which the program prints, have it already.
        #: (String source, String line, String file, RubyOptions options) -> void
        def shebang_warning(source, line, file, options)
          shebang = line.each_line.first.to_s
          return if options.xflag || options.switches.verbose.nil?
          return unless shebang.start_with?("#!") && shebang.include?("ruby") && shebang.end_with?("\r\n")

          number = source.each_line.find_index { |text| text.equal?(shebang) || text == shebang }.to_i + 1
          warn "#{file}:#{number}: warning: shebang line ending with \\r may cause problems"
        end

        # -S: the script in RUBYPATH's directories, then PATH's (the current
        # directory with no PATH), as ruby's dln_find_file_r searches them.
        # A name that starts with "/", "./" or "../" is a path already.
        #: (String name, ?verbose: bool) -> String
        def searched(name, verbose: false)
          return name if name.match?(%r{\A\.{0,2}/})

          rubypath = ENV.fetch("RUBYPATH", nil)
          (rubypath && found_in(name, rubypath, verbose)) || found_in(name, ENV.fetch("PATH", "."), verbose) || name
        end

        # MAXPATHLEN, the buffer that dln_find_1 builds each path in.
        SEARCH_BUFFER = 1024

        # The first regular file `name` in the directories of `list`, or
        # nil, as dln_find_1 builds each path: a directory "~" or "~/..."
        # starts at HOME, an empty one is the current directory, and a path
        # that does not fit the buffer is skipped, with ruby's warning under
        # -w that shows what fit.
        #: (String name, String list, bool verbose) -> String?
        def found_in(name, list, verbose)
          if name.bytesize >= SEARCH_BUFFER
            warn "zr: warning: openpath: pathname too long (ignored)\n\tFile #{clip(name)}\n\n" if verbose
            return nil
          end
          list.split(File::PATH_SEPARATOR, -1).each do |dir|
            path = +""
            fits = lambda do |part|
              next true if path.bytesize + part.bytesize <= SEARCH_BUFFER - 2

              warn "zr: warning: openpath: pathname too long (ignored)\n\tDirectory #{clip(path)}\n\tFile #{clip(name)}\n\n" if verbose
              false
            end
            unless dir.empty?
              if dir.match?(%r{\A~(?:/|\z)})
                home = ENV.fetch("HOME", nil)
                next if home && !fits.call(home)

                path << home.to_s
                dir = dir[1..].to_s
              end
              next unless fits.call(dir)

              path << dir
              path << "/" unless path.end_with?("/")
            end
            next unless fits.call(name)

            candidate = path + name
            return candidate if File.file?(candidate)
          end
          nil
        end

        # dln_find_1 shows at most 100 bytes of a name, then "...".
        #: (String text) -> String
        def clip(text) = "\"#{text.byteslice(0, 100)}\"#{"..." if text.bytesize > 100}"

        # -c, -y and --dump: the program is parsed, not run. A syntax error
        # gets ruby's report and status 1. Else -y prints nothing (prism
        # has no parser trace), -c and --dump=syntax print "Syntax OK", and
        # --dump=parsetree prints prism's tree.
        #: (String source, String file, RubyOptions options) -> void
        def dump(source, file, options)
          require_relative "../../parse"
          require_relative "../../hir/syntax_report"
          result = Zr.parse(source, filepath: file, **options.switches.parse_options(true))
          # ruby prints the warnings also for a program that does not parse.
          $stderr.write(Refusals.warning_lines(result, file, options.switches.verbose))
          unless result.errors.empty?
            $stderr.write(Refusals.syntax_text("zr", Hir::SyntaxReport.error(result, file)))
            exit 1
          end
          tree = parse_tree(result) if options.dumps.include?(:parsetree)
          syntax = options.dumps.include?(:syntax)
          # ruby prints "Syntax OK" with C's printf and the tree through
          # $stdout, which it flushes. So a terminal shows "Syntax OK" first,
          # and on macOS a pipe or a file gets it last, when C's buffer is
          # flushed. A ruby on musl (Alpine) gives it first there too.
          first = $stdout.tty? || RUBY_PLATFORM.end_with?("-musl")
          puts "Syntax OK" if syntax && first
          $stdout.write(tree) if tree
          puts "Syntax OK" if syntax && !first
        end

        #: (Prism::ParseResult result) -> String
        def parse_tree(result)
          require_relative "../parse_tree"
          ParseTree.text(result.value)
        end

        # Prints the line of an error before the program runs, as ruby
        # does, and exits 1: after the program's name, or the script's.
        #: (String line, ?prefix: String, ?hint: String?) -> bot
        def fatal(line, prefix: as_ruby? ? $PROGRAM_NAME : "zr", hint: nil)
          warn "#{prefix}: #{line}"
          warn hint if hint
          exit 1
        end

        # Whether zr runs under the name `ruby`, as a launcher that stands
        # for ruby names it (Runner.pinned_launcher).
        #: () -> bool
        def as_ruby? = File.basename($PROGRAM_NAME) == "ruby"

        # How the build treats a require that no file answers: it refuses it
        # (true), leaves it to raise LoadError when it runs
        # (`--allow-runtime-require`, false), or under `zr build` notes it
        # (:warn); `run` and `diff` print the program's output alone.
        #: (Hash[Symbol, untyped] opts) -> (bool | :warn)
        def gate(opts)
          if opts[:runtime_require] then false
          elsif name == "build" then :warn
          else true
          end
        end

        # The build and the run of a program: `source`, the text of the
        # file `input` ("-e" or "-" for a program with no file), with the
        # ruby switches `switches`.
        #: (Hash[Symbol, untyped] opts, String source, String input, Hir::Switches switches) -> void
        def compile(opts, source, input, switches)
          gems = Options.gem_set(source)

          target = Options.target_for(opts[:triple], opts[:emit], name)
          emit = opts[:emit] || ("wasm" if target.outputs == [:wasm])
          usage_error("--link applies only to a native binary") if emit && !opts[:link].empty?
          Refusals.refuse(input, name, emit, target, chosen: !opts[:triple].nil?)
          wasmtime! if name == "run" && emit == "wasm"

          Paths.root = opts[:root]
          link = Config.current.link + opts[:link]
          trace = Options.trace?(opts)
          gate = gate(opts)
          # The run cache's entry for a runtime of `digest`.
          # @type var entry: ^(String) -> Zr::Cache::Run
          entry = lambda do |digest|
            Zr::Cache::Run.new(input, source: source, switches: switches, target: target, digest: digest, link: link, gems: gems, gate: gate,
                                      trace: trace)
          end
          cache = @missed || kept_run(target, opts[:args], &entry) if name == "run" && emit.nil?
          require_relative "../../runtime"
          require_relative "../../native/build"
          # Under ruby, the first parse turns the parse cache on (`Zr.parse_cache`). A compiled
          # compiler turns it on here. A program that calls eval includes the
          # same files but never comes here, so it never writes to the cache.
          require_relative "../../cache/parse" if Binary.running?
          if name == "run" && emit.nil? && Zr::Cache::Run.wanted?
            cache ||= entry.call(Runtime.for(target).digest)
          end
          options = BuildOptions.new(target: target, gem_set: gems, gate: gate, trace: trace, switches: switches)
          program = lower(input, options, source: source, assemble: emit.nil?)
          status = Paths.tmpdir("zr-build-") do |work|
            # @type var write: ^(String) -> Object?
            write = lambda do |out|
              case emit
              when "obj" then object(program, out)
              when "wasm" then wasm(program, out, opts[:args], output: opts[:output])
              else native(program, out, work, opts[:args], link: link, cache: cache)
              end
            end
            # `zr build` puts its output in place in one rename (`Paths.publish`).
            name == "run" ? write.call(File.join(work, "program")) : Paths.publish(File.expand_path(opts[:output]), &write)
          end
          print Gems.table(program.gems) if opts[:print_gems]
          require_relative "../../cache/janitor"
          Zr::Cache::Janitor.trim
          kept = @exec
          exec(Runner.program_env, [kept, kept], *opts[:args]) if kept
          Runner.exit_as(status) if status.is_a?(Process::Status)
        end

        # A `zr run` whose binary is in the run cache: execs the binary now,
        # before zr starts again with the collector limits (40 ms). This process then is the program, so
        # its status and signals are the program's own. Does nothing for any
        # other command, for a `zr run` that needs a build, and in the second
        # start (whose first start already looked).
        #: (Array[String] argv) -> void
        def kept!(argv)
          ruby = CLI.ruby_mode?(argv)
          return unless (argv.first == "run" || ruby) && !ENV.key?(GcTuning::ADDED) && !Binary.running?

          require_relative "../../cache/run"
          return unless Zr::Cache::Run.wanted? && Refusals.host_refusal.nil?

          if ruby
            found = kept_ruby(argv) or return
            opts, source, input, switches = found
          else
            opts = Options.parse("run", argv.drop(1))
            input = opts[:input]
            return unless File.file?(input)

            source = File.read(input)
            switches = RubyOptions.new.tap { |options| options.shebang!(source) }.switches
          end
          return if opts[:emit] || opts[:triple]

          target = Target.default
          return unless target.runs_here? && target.refusal(nil).nil?

          Paths.root = opts[:root]
          # A set that does not resolve goes on to the build, which says why.
          gems = kept_gems(source) or return
          digest = RuntimeSources.for(target).runtime_digest or return
          cache = Zr::Cache::Run.new(input, source: source, switches: switches, target: target, digest: digest,
                                            link: Config.current.link + opts[:link], gems: gems, gate: gate(opts), trace: Options.trace?(opts))
          kept = cache.hit
          begin
            exec(Runner.program_env, [kept, kept], *opts[:args]) if kept
          rescue Errno::ENOENT
            nil # another zr replaced the entry since the hit: build it
          end
          # The build keeps its binary here, with no second digest.
          @missed = cache
        end

        # A binary's functions are assembled as they are lowered, so the IR of
        # a large program is never all in memory at once (`Native::Build.lower`).
        # Returns a `Zr::Program`. `source` is the text of `input`, which
        # ruby mode gives for a program with no file.
        #: (String input, BuildOptions options, ?source: String, ?assemble: bool) -> Program
        def lower(input, options, source: File.read(input), assemble: false)
          lower!(input, options, source: source, assemble: assemble, invalid: :program)
        rescue Refused => e
          warn Refusals.refusal_report(e)
          exit REFUSED
        rescue InvalidProgram => e
          warn "zr: #{e.message}"
          exit REFUSED
        rescue BuildError => e
          abort "zr: #{e.message}"
        end

        # The program of `input`, as `lower` gives it, for `Zr.build` too.
        # A form that zr refuses raises Refused. A program that ruby's
        # compiler rejects or that does not parse, with `invalid: :program`,
        # lowers to one that prints ruby's error, as ruby would run it;
        # with `invalid: :raise`, it raises InvalidProgram. A backend that
        # cannot compile the code raises BuildError.
        #: (String input, BuildOptions options, source: String, assemble: bool, ?invalid: :program | :raise) -> Program
        def lower!(input, options, source:, assemble:, invalid: :raise)
          built(source, input, options, source: source, assemble: assemble)
        rescue Refused => e
          # A form of the program that ruby's compiler refuses (`Hir::Invalid`)
          # ends as ruby's SyntaxError does, before any of the program runs.
          raise unless (text = Refusals.invalid_program(input, e))
          raise InvalidProgram.new(e.message, file: e.file, line: e.line) if invalid == :raise

          warn "zr: warning: #{input} does not compile in ruby. The output prints ruby's SyntaxError and exits with status 1" if name == "build"
          built(text, input, options.with(gate: false, trace: false), source: source, assemble: assemble)
        rescue Backend::Refused => e
          # A backend refuses code that the front end let through: a limit or
          # a defect in zr, not a form of Ruby that the program must avoid.
          raise BuildError, "zr cannot compile this program: #{e.message}. This is a limit or a defect in zr. Report it at #{ISSUES_URL}."
        rescue SyntaxError => e
          # For a program that does not parse, ruby prints the parse's
          # warnings and a report, and exits 1. The binary does the same
          # (`Refusals.syntax_error_program`). A required file that does not
          # parse raises when the require runs (`Loader#parsed_unit`).
          warned = Refusals.syntax_warnings(input, source, options.switches)
          raise InvalidProgram, "a required file does not parse: #{e.message.lines.first.chomp}" unless warned
          raise InvalidProgram.new(e.message.lines.first.chomp, file: input) if invalid == :raise

          warn "zr: warning: #{input} does not parse. The output prints ruby's syntax error and exits with status 1" if name == "build"
          # The -r requires still run before it, and their exit handlers after.
          built(Refusals.syntax_error_program(input, e, warned), input, options.with(gate: false, trace: false), source: source,
                                                                                                    assemble: assemble)
        end

        # The program of `text` for the script `input`, whose own text is
        # `source`. In place of a script that does not compile, `text` is the
        # program that reports it. The run cache keeps that one too, under
        # the digest of the script's own bytes, so an edit to the script
        # builds again; it was built each time (4 s for `zr -e "p ("`).
        #: (String text, String input, BuildOptions options, source: String, assemble: bool) -> Program
        def built(text, input, options, source:, assemble:)
          return Program.build(text, input, options) unless assemble

          program = Native::Build.lower(text, input, options, sources: name == "run")
          path = File.expand_path(input)
          sources = program.sources
          return program if text.equal?(source) || sources.nil? || !sources.key?(path)

          program.with(sources: sources.merge(path => Digest::SHA256.hexdigest(source)))
        end

        private

        # `zr run --emit wasm` runs the module with wasmtime. Without it, stop
        # before the build.
        #: () -> void
        def wasmtime!
          require_relative "../../doctor"
          return if Zr::Doctor.which("wasmtime")

          abort "zr: zr run --emit wasm needs wasmtime, and it is not on the PATH. Install it from https://wasmtime.dev, " \
                "or use 'zr build --emit wasm' to write the module only."
        end

        #: (Program program, String out) -> nil
        def object(program, out)
          why = program.write_object(out)
          abort "zr: #{why}" if why
          nil
        end

        # With `--wasm-split`, `zr build` writes the runtime module beside
        # the program module's `output` (`out` is its draft), and `zr run`
        # keeps it in the cache, where the next run finds it.
        #: (Program program, String out, Array[String] rest, ?output: String?) -> Process::Status?
        def wasm(program, out, rest, output: nil)
          if Config.current.wasm_split?
            split = name == "run" || output.nil? ? File.join(Paths.cache, "wasm-split") : File.dirname(File.expand_path(output))
          end
          why = program.write_wasm(out, split: split)
          abort "zr: #{why}" if why
          return nil unless name == "run"

          # The module can see the working directory, as a ruby program can,
          # at its own path, and starts there (PWD, zr_wasi_start_cwd): the
          # build wrote absolute paths. The engine's stack holds more wasm
          # frames than the shadow stack holds records, so a recursion that
          # is too deep raises SystemStackError (kernel/os/wasi/stack.rb).
          # `system`, not `exec`, so that the build directory goes away after
          # the run, as for a binary.
          require_relative "../../backend/wasm"
          preload = [] #: Array[String]
          if split && (runtime = Backend::Wasm.runtime_of(File.binread(out)))
            preload = ["--preload", "#{Backend::Wasm::Codegen::RUNTIME}=#{File.join(split, runtime)}"]
          end
          here = Dir.pwd
          interrupt = Signal.trap("INT") { nil }
          system("wasmtime", "run", "-W", "max-wasm-stack=#{6 << 20}", "--dir", ".", "--dir", "#{here}::#{here}", "--env", "PWD=#{here}", *preload, out, *rest)
          Signal.trap("INT", interrupt)
          $?
        end

        # @rbs program: Program
        # @rbs out: String
        # @rbs work: String
        # @rbs rest: Array[String]
        # @rbs link: Array[String]
        # @rbs cache: Zr::Cache::Run?
        # @rbs return: Object?
        def native(program, out, work, rest, link: [], cache: nil)
          why = program.write_binary(out, work: work, link: link)
          abort "zr: #{why}" if why
          return unless name == "run"

          kept = cache&.keep(out, program, work)
          # A kept binary outlives the build directory: zr execs it once the
          # build is gone, so the program has zr's pid, as a ruby script has
          # ruby's.
          return @exec = kept if kept

          Runner.run_binary(out, rest)
        rescue Refusal => e
          # A C extension that the link cannot take (a missing C API
          # function, C++ exceptions in embed mode...): the message says
          # what to change.
          warn "zr: #{e.message}"
          exit REFUSED
        end

        # Ruby mode's program for `kept!`: the options of `zr run`, the text,
        # the file and the switches. It reads the program now (after -C),
        # and `ruby` uses what it read. nil for a command line that does
        # not run a program from the cache: -v and -c print, and an error
        # is for `ruby` to report.
        #: (Array[String] argv) -> [Hash[Symbol, untyped], String, String, Hir::Switches]?
        def kept_ruby(argv)
          options = RubyOptions.parse(argv)
          return nil if options.refused || options.dumps? || options.version || options.version_only || options.copyright || options.help?
          return nil unless options.runs?($stdin.tty?)

          # ruby warns as it reads the switches, before the program runs.
          options.warnings.each { |line| warn line }
          options.warnings.clear
          @options = options
          source, file = @given = given(options)
          [Options.parse("run", [*options.zr, "--", file, *options.args]), source, file, options.switches]
        rescue RubyOptions::Invalid
          nil
        end

        # The GemSet of a `zr run` before the build, or nil when it does not
        # resolve.
        #: (String source) -> GemSet?
        def kept_gems(source)
          require_relative "../../gem_set"
          GemSet.resolve(requests: GemSet.requests(source))
        rescue GemSet::Unresolved
          nil
        end

        # A program that ran before with the same sources runs from the run
        # cache, and zr exits as it does. This loads only the digests, not the
        # compiler. Returns the cache for the build otherwise, or nil when zr
        # needs a build to know the runtime's digest.
        # The block gives the cache's entry for the runtime's digest.
        #: (Target target, Array[String] args) { (String) -> Zr::Cache::Run } -> Zr::Cache::Run?
        def kept_run(target, args)
          require_relative "../../cache/run"
          return nil unless Zr::Cache::Run.wanted?

          digest = RuntimeSources.for(target).runtime_digest or return nil
          cache = yield(digest)
          kept = cache.hit
          exec(Runner.program_env, [kept, kept], *args) if kept
          cache
        end
      end
    end
  end
end
