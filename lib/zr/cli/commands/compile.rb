# frozen_string_literal: true

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
      # A compile command also holds what a process that serves builds
      # needs: the binary that a `zr run` found in the run cache
      # (`kept!`), and the block that takes a binary in place of running it
      # (`served!`).
      #
      # In `Commands`, `Cache` names the command `cache`: the caches are
      # `Zr::Cache`.
      class Compile < Command
        # @rbs @missed: Zr::Cache::Run?
        # @rbs @exec: String?
        # @rbs @served: (^(String, Array[String], bool) -> Object?)?
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
          return CLI::Help.show if options.help?

          options.warnings.each { |line| warn line }
          Refusals.pinned!
          if (why = options.refused)
            warn "zr: #{why}"
            exit REFUSED
          end
          # -v gives ruby's description, as ruby does; --version gives zr's.
          puts Zr.ruby_description(Target.default.ruby_platform) if options.version
          puts Version::LINE if options.version_only
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
          # script runs as with -x, also from standard input.
          first = source.each_line.first.to_s
          options.xflag! if first.start_with?("#!") && !first.include?("ruby")
          line = options.xflag ? source.each_line.find { |text| text.start_with?("#!") && text.include?("ruby") } : source
          fatal("no Ruby script found in input (LoadError)", prefix: file) unless line
          options.shebang!(line)
          shebang_warning(source, line, file, options)
          [source, file]
        rescue SystemCallError => e
          # strerror's words, without what ruby's message adds after them.
          fatal("#{e.message.sub(/ @ .*\z/m, "")} -- #{name} (LoadError)")
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
          unless result.errors.empty?
            $stderr.write(Refusals.syntax_text("zr", Hir::SyntaxReport.error(result, file)))
            exit 1
          end
          tree = parse_tree(result) if options.dumps.include?(:parsetree)
          syntax = options.dumps.include?(:syntax)
          # ruby prints "Syntax OK" with C's printf and the tree through
          # $stdout, which it flushes. So a terminal shows "Syntax OK" first,
          # and a pipe or a file gets it last, when C's buffer is flushed.
          puts "Syntax OK" if syntax && $stdout.tty?
          $stdout.write(tree) if tree
          puts "Syntax OK" if syntax && !$stdout.tty?
        end

        #: (Prism::ParseResult result) -> String
        def parse_tree(result)
          require_relative "../parse_tree"
          ParseTree.text(result.value)
        end

        # Prints the line of an error before the program runs, as ruby
        # does, and exits 1: after the program's name, or the script's.
        #: (String line, ?prefix: String) -> bot
        def fatal(line, prefix: "zr")
          warn "#{prefix}: #{line}"
          exit 1
        end

        # The build and the run of a program: `source`, the text of the
        # file `input` ("-e" or "-" for a program with no file), with the
        # ruby switches `switches`.
        #: (Hash[Symbol, untyped] opts, String source, String input, Hir::Switches switches) -> void
        def compile(opts, source, input, switches)
          gems = Options.gem_set(opts)

          target = Options.target_for(opts[:triple], opts[:emit], name)
          emit = opts[:emit] || ("wasm" if target.outputs == [:wasm])
          usage_error("--link applies only to a native binary") if emit && !opts[:link].empty?
          Refusals.refuse(input, name, emit, target, chosen: !opts[:triple].nil?)
          wasmtime! if name == "run" && emit == "wasm"

          Paths.root = opts[:root]
          link = Config.current.link + opts[:link]
          trace = Options.trace?(opts)
          # The run cache's entry for a runtime of `digest`.
          # @type var entry: ^(String) -> Zr::Cache::Run
          entry = lambda do |digest|
            Zr::Cache::Run.new(input, source: source, switches: switches, target: target, digest: digest, link: link, gems: gems, trace: trace)
          end
          cache = @missed || kept_run(target, opts[:args], &entry) if name == "run" && emit.nil?
          require_relative "../../runtime"
          require_relative "../../native/build"
          # Under ruby, lib/zr/prism.rb turns the parse cache on. A compiled
          # compiler turns it on here. A program that calls eval includes the
          # same files but never comes here, so it never writes to the cache.
          require_relative "../../cache/parse" unless HOSTED
          if name == "run" && emit.nil? && Zr::Cache::Run.wanted?
            cache ||= entry.call(Runtime.for(target).digest)
          end
          # Only `zr build` notes a require that will raise LoadError when it
          # runs; `run` and `diff` print the program's output alone.
          gate = if opts[:runtime_require] then false
                 elsif name == "build" then :warn
                 else true
                 end #: bool | :warn
          program = lower(input, target, source: source, switches: switches, assemble: emit.nil?, gem_set: gems, gate: gate, trace: trace)
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
          kept = @exec
          exec(Runner.program_env, [kept, kept], *opts[:args]) if kept
          Runner.exit_as(status) if status.is_a?(Process::Status)
        end

        # In a build that the server runs (lib/zr/server.rb), `zr run` gives
        # its binary to the block, in place of running it: the path, the
        # program's arguments, and whether the path is in the build directory,
        # which goes away when the build ends.
        #: () { (String binary, Array[String] rest, bool temp) -> Object? } -> void
        def served!(&back)
          @served = back
        end

        # A `zr run` whose binary is in the run cache: execs the binary now,
        # before zr looks for a compiled compiler or starts again with the
        # collector limits (40 ms each). This process then is the program, so
        # its status and signals are the program's own. Does nothing for any
        # other command, for a `zr run` that needs a build, and in the second
        # start (whose first start already looked).
        #: (Array[String] argv) -> void
        def kept!(argv)
          ruby = CLI.ruby_mode?(argv)
          return unless (argv.first == "run" || ruby) && !ENV.key?(GcTuning::ADDED) && !Host.compiled?

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
          gems = kept_gems(opts) or return
          digest = RuntimeSources.for(target).runtime_digest or return
          cache = Zr::Cache::Run.new(input, source: source, switches: switches, target: target, digest: digest,
                                            link: Config.current.link + opts[:link], gems: gems, trace: Options.trace?(opts))
          kept = cache.hit
          exec(Runner.program_env, [kept, kept], *opts[:args]) if kept
          # The build keeps its binary here, with no second digest.
          @missed = cache
        end

        # A binary's functions are assembled as they are lowered, so the IR of
        # a large program is never all in memory at once (`Native::Build.lower`).
        # Returns a `Zr::Program`. `source` is the text of `input`, which
        # ruby mode gives for a program with no file.
        # @rbs input: String
        # @rbs target: Target
        # @rbs source: String
        # @rbs switches: Hir::Switches
        # @rbs assemble: bool
        # @rbs gem_set: GemSet?
        # @rbs gate: bool | :warn
        # @rbs trace: bool
        # @rbs return: Program
        def lower(input, target, source: File.read(input), switches: Hir::Switches::NONE, assemble: false, gem_set: nil, gate: false, trace: false)
          unless assemble
            return Program.build(source, input, target: target, gem_set: gem_set, gate: gate, trace: trace, switches: switches)
          end

          Native::Build.lower(source, input, target: target, sources: name == "run", gem_set: gem_set, gate: gate, trace: trace, switches: switches)
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
          # 1. The binary does the same, with ruby's own report. A required
          # file that does not parse raises when the require runs
          # (`Loader#parsed_unit`).
          # A program with no file: ruby's report has no syntax_suggest part.
          given = !File.file?(input) && e.respond_to?(:path) && e.path == input
          report = given ? Refusals.syntax_text(input, e) : Refusals.syntax_report(input, verbose: switches.verbose)
          unless report
            warn "zr: a required file does not parse: #{e.message.lines.first.chomp}"
            exit REFUSED
          end
          warn "zr: warning: #{input} does not parse. The output prints ruby's syntax error and exits with status 1" if name == "build"
          # The -r requires still run before it, and their exit handlers after.
          Program.build(syntax_error_program(input, e, report), input, target: target, gem_set: gem_set, switches: switches)
        end

        private

        # The program that ends as ruby does for a script that does not
        # parse, after the -r requires ran: the parse's warnings, then the
        # error as error_print writes it, through SyntaxError#detailed_message,
        # which syntax_suggest (and the program) may extend. The api of
        # syntax_suggest is required here, as its detailed_message requires
        # it by a name that the build cannot see.
        #: (String input, SyntaxError error, String report) -> String
        def syntax_error_program(input, error, report)
          warned = report[0, report.index("#{input}: ") || 0]
          <<~RUBY
            require "syntax_suggest/api" if defined?(SyntaxSuggest)
            error = SyntaxError.new(#{error.message.inspect})
            error.instance_variable_set(:@path, #{input.inspect})
            $stderr.write(#{warned.inspect}, #{input.inspect}, ": ", error.detailed_message(highlight: false), "\\n")
            exit 1
          RUBY
        end

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

        #: (Program program, String out, Array[String] rest) -> Process::Status?
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
          served = @served
          return served.call(kept || out, rest, kept.nil?) if served
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
        #: (Hash[Symbol, untyped] opts) -> GemSet?
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
