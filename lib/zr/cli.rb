# frozen_string_literal: true

require "rbconfig"
require_relative "version"
require_relative "paths"
require_relative "config"
require_relative "target"
require_relative "tune"

module Zr
  # The `zr` command: `exe/zr` in a checkout, and the gem's executable
  # once it is installed. The repository's own tools (tests, bootstrap,
  # benchmarks, generated tables) are rake tasks.
  #
  # The parser is a small table, not OptionParser: optparse requires
  # `pp`, which calls eval, and a compiler that zr compiles would then
  # have to include eval support.
  module CLI
    USAGE = <<~TEXT.freeze
      Usage: zr <command> [options]

      Commands:
        run <file.rb> [args...]     compile a program, run it, then delete the build
        build <file.rb> -o <out>    compile a program to a binary, a WASI module or an object
        machine <file.rb> -o <out>  compile one typed-Ruby kernel file (for runtime work)
        targets                     list the targets, and what this host can build
        gems [<file.rb>]            list the gems that a build reads, and their sources
        inspect <binary>            print the gems that a binary was built with
        diff <file.rb> [args...]    run a program under ruby and as a zr binary, and compare
        doctor                      check this host: ruby, wasmtime, OpenSSL, gems, cache
        cache [path|size|clean]     show or clean the build cache
        version                     print the version
        help [<command>]            print help for zr or for one command

      Exit status: 0 success; 1 error; 2 usage error or a bad ZR_* value;
      3 zr does not support the program, the target or this ruby; 130 Ctrl-C.
      `zr run` exits with the program's status.
      Environment variables: #{DOCS_URL}/reference/environment-variables.md
    TEXT

    OUTPUT = "  -o, --output <path>    write the output to <path>\n"
    PRINT_GEMS = "  --print-gems           print the gems that the output was built with\n"
    # `run` and `build` only: a machine file requires nothing.
    GEMS = <<~TEXT.gsub(/^/, "  ")
      --gem <name>=<version|dir>
                             use this gem in place of the Gemfile.lock's or zr's
                             own: an installed version, or a directory with a
                             gemspec or lib/; once for each gem
      --gemfile <path>       read the gems of <path>'s lock before zr's own, as
                             `bundle exec ruby` does (BUNDLE_GEMFILE also names it)
      --allow-runtime-require
                             let a require in the program's files that zr cannot
                             find wait for the run time (the binary then carries
                             the compiler to compile what it finds then)
    TEXT
    OPTIONS = <<~TEXT.sub("  -h, --help", "#{GEMS}  -h, --help")
      Options:
        --emit <kind>          binary (the default), obj, or wasm
        --target <triple>      build for <triple> (see `zr targets`)
        --path-root <dir>      write source paths in the output as <dir> plus the
                               path below zr's root or the working directory,
                               so that two checkouts make the same bytes
        --link <arg>           give <arg> to the system linker (cc) for a native
                               binary: an object, an archive, -framework <name>,
                               -Wl,<flags>; once for each argument
        -h, --help             print this help
    TEXT

    HELP = {
      "run" => <<~TEXT,
        Usage: zr run [options] <file.rb> [args...]

        Compiles <file.rb>, runs it with [args...], then deletes the build.
        Every word after <file.rb> goes to the program. With --emit wasm,
        wasmtime runs the module.

        #{OPTIONS.sub("binary (the default), obj, or wasm", "binary (the default) or wasm")}
      TEXT
      "build" => <<~TEXT,
        Usage: zr build [options] <file.rb> -o <out>

        Compiles <file.rb> with the zr runtime. The output is a native
        binary, a WASI module (--emit wasm, or a wasm32 --target) or an
        object file (--emit obj).

        #{OPTIONS.sub("Options:\n", "Options:\n#{OUTPUT}#{PRINT_GEMS}")}
      TEXT
      "machine" => <<~TEXT,
        Usage: zr machine [options] <file.rb> -o <out>

        Compiles one file of typed Ruby (one `module Zr::Kern`, as in
        lib/zr/runtime/kernel), without the zr runtime.

        #{OPTIONS.sub(GEMS, "").sub("Options:\n", "Options:\n#{OUTPUT}")}
      TEXT
      "doctor" => <<~TEXT,
        Usage: zr doctor

        Checks what zr needs on this host, and prints ok, warn or fail for
        each: the ruby version, the targets this host builds, wasmtime,
        OpenSSL 3, the standard library, the cache and the compiled compiler.
        Exits with status 1 if a check fails.
      TEXT
      "gems" => <<~TEXT,
        Usage: zr gems [--gem <name>=<version|dir>]... [--gemfile <path>] [--json] [<file.rb>]

        Lists each gem that a build can read, with its version and its
        source: stdlib (ruby 4.0.7's library in zr), port (a gem with a C
        part that zr ports), Gemfile.lock, or --gem. With <file.rb>, lists
        only the gems that the build of <file.rb> reads.

        --json                 print JSON, one object for each gem
        --target <triple>      the target of the build of <file.rb>
      TEXT
      "inspect" => <<~TEXT,
        Usage: zr inspect [--json] <binary>

        Prints the gems that zr built <binary> with, from the manifest that
        each binary, object and WASI module carries: the zr and ruby
        versions, the target, and each gem with its version and source.
      TEXT
      "diff" => <<~TEXT,
        Usage: zr diff [options] <file.rb> [args...]

        Runs <file.rb> with [args...] under ruby and as a zr binary, and
        compares stdout, stderr, the exit status and the signal. Prints
        the kind of difference (same, output-diff, exception-diff,
        status-diff, crash, timeout, refused or build-error), then a diff
        of each part. Exits with status 0 only when the two are the same.

        ruby reads the same --gem directories, and runs as `bundle exec
        ruby` does with --gemfile or BUNDLE_GEMFILE. The two runs can
        differ where ruby has other versions of its gems than zr: see
        `zr gems`.

        #{OPTIONS.sub(/^  --emit .*\n/, "")}
      TEXT
      "targets" => <<~TEXT,
        Usage: zr targets

        Lists each target that zr builds for, the outputs it makes for the
        target (binary, obj, wasm), and the outputs that this host can make.
      TEXT
      "version" => <<~TEXT,
        Usage: zr version

        Prints zr's version and the ruby version that it matches:
        zr #{VERSION} (for ruby #{RUBY}). `zr --version` and `zr -v` do the same.
      TEXT
      "help" => <<~TEXT,
        Usage: zr help [<command>]

        Prints the commands of zr, or the help of one command.
        `zr <command> --help` does the same.
      TEXT
      "cache" => <<~TEXT
        Usage: zr cache [path|size|clean [--all]]

        path          print the cache directory (the default)
        size          what the cache holds, by kind
        clean         delete the files that this zr does not use, and the
                      compiled compilers that older zr versions kept
        clean --all   delete every file in the cache, also this zr's own;
                      the next build makes them again

        An installed zr also cleans its cache when it grows past
        ZR_CACHE_MAX_GB (default 5).
      TEXT
    }.freeze

    # The commands that compile.
    COMPILE = %w[run build machine].freeze
    EMITS = { "binary" => nil, "obj" => "obj", "wasm" => "wasm" }.freeze

    # Exit status 3: zr does not support the program or the target. The
    # test harness counts this separately from zr's defects.
    REFUSED = 3

    module_function

    # Sets the collector limits and YJIT for a compile (`Tune`). With
    # `later`, only the first step of heavy work tunes, so a warm build
    # pays for neither.
    def tune!(script = nil, later: false)
      later ? Tune.later(script, ARGV) : Tune.now(script, ARGV)
    end

    # Why this compiler must not build on a ruby of `version`, or nil
    # when it runs there.
    def host_refusal(version = RUBY_VERSION)
      return if Zr.supported_ruby?(version)

      "zr #{VERSION} runs on ruby #{RUBY} or a later 4.0 release. " \
        "Install ruby #{RUBY}: #{DOCS_URL}/how-to/install.md"
    end

    # A note for a ruby that zr runs on but is not tested with, or nil.
    def host_note(version = RUBY_VERSION)
      return if version == RUBY || !Zr.supported_ruby?(version)

      "zr #{VERSION} is tested with ruby #{RUBY}; this is ruby #{version}"
    end

    # Stops a build on a ruby that zr does not run on, before it reads
    # the program. Warns once on a ruby that it is not tested with.
    def pinned!(version = RUBY_VERSION)
      if (note = host_note(version))
        warn "zr: warning: #{note}"
        return
      end
      return unless (why = host_refusal(version))

      warn "zr: #{why}"
      exit REFUSED
    end

    # The errors that say what the user must change, not a defect in zr.
    # They print their message only. Named as strings: not every command
    # loads the file that defines each one.
    EXPECTED = %w[Zr::Config::Invalid Zr::SourceChanged Zr::GemSet::Unresolved Zr::Paths::Missing].freeze
    # The errors of a directory that zr cannot write to or that is full.
    UNWRITABLE = %w[EACCES EROFS ENOSPC EPERM].freeze

    # Runs the command, and turns an error that escapes it into one line
    # and an exit status: 130 for Ctrl-C, 2 for a bad setting, 1 for any
    # other error. An error that zr did not expect is a defect: the line
    # says so and where to report it. ZR_DEBUG=1 shows the backtrace.
    def guard
      yield
    rescue Interrupt
      # The `ensure` clauses of the build have removed its temp files.
      exit 130
    rescue StandardError => e
      raise if Config.debug?

      warn "zr: #{error_line(e)}"
      exit(e.is_a?(Config::Invalid) ? 2 : 1)
    end

    # The line that `guard` prints for `error`.
    def error_line(error)
      return error.message if EXPECTED.include?(error.class.name)
      return "#{error.message}#{cache_hint(error)}" if error.is_a?(SystemCallError)

      "internal error: #{error.class}: #{error.message}. This is a defect in zr. Report it at #{ISSUES_URL} " \
        "with the output of 'zr doctor'. Set ZR_DEBUG=1 to see the backtrace."
    end

    # For an error that writing into zr's cache gave, how to fix it.
    def cache_hint(error)
      return "" unless UNWRITABLE.any? { |name| Errno.const_get(name) === error }

      dirs = [Config.current.cache, Paths.user_cache, File.join(Paths::ROOT, "tmp/cache")].compact
      return "" unless dirs.any? { |dir| error.message.include?(dir) }

      ". Set XDG_CACHE_HOME (or ZR_CACHE) to a directory that you can write to, or run 'zr cache clean'"
    rescue StandardError
      ""
    end

    # The commands that take no file and no option but -h and --help.
    PLAIN = %w[targets doctor version].freeze

    def start(argv)
      args = argv.dup
      command = args.shift
      command = "version" if %w[--version -v].include?(command)
      command = "help" if %w[-h --help].include?(command)
      if HELP.key?(command) && !COMPILE.include?(command) && command != "gems" &&
         args.take_while { |word| word.start_with?("-") }.intersect?(%w[-h --help])
        help(command)
        exit
      end
      usage_error("unexpected argument '#{args.first}'", command) if PLAIN.include?(command) && !args.empty?
      case command
      when *COMPILE then compile(command, args)
      when "targets" then targets
      when "gems", "inspect", "diff"
        require_relative "gems_command"
        GemsCommand.public_send(command, args)
      when "doctor" then exit(doctor ? 0 : 1)
      when "cache" then cache(args)
      when "version" then puts "zr #{VERSION} (for ruby #{RUBY})"
      when "help" then help(args.first)
      when nil
        warn USAGE
        exit 2
      when /\A-/ then usage_error("unknown option '#{command}'")
      else
        near = HELP.keys.find { |name| near?(command, name) }
        usage_error("unknown command '#{command}'#{"; did you mean '#{near}'?" if near}")
      end
    end

    # Whether `word` is one edit (a letter added, removed, changed, or
    # two letters swapped) from `name`.
    def near?(word, name)
      return false if (word.size - name.size).abs > 1

      a, b = [word, name].sort_by(&:size)
      i = 0
      i += 1 while i < a.size && a[i] == b[i]
      return a[i..] == b[(i + 1)..] if a.size < b.size

      a[(i + 1)..] == b[(i + 1)..] || (a[i] == b[i + 1] && a[i + 1] == b[i] && a[(i + 2)..] == b[(i + 2)..])
    end

    def doctor
      require_relative "doctor"
      Doctor.run
    end

    # `zr cache path`, `size` or `clean [--all]`.
    def cache(args)
      require_relative "cache/janitor"
      verb = args.shift || "path"
      extra = args - (verb == "clean" ? ["--all"] : [])
      usage_error("unexpected argument '#{extra.first}'", "cache") unless extra.empty?
      case verb
      when "path" then puts Paths.cache
      when "size"
        files = Cache::Janitor.all
        files.group_by { |path| Cache::Janitor.kind(path) }.sort_by { |_, group| -Cache::Janitor.bytes(group) }.each do |kind, group|
          puts format("%6d MB  %5d  %s", Cache::Janitor.megabytes(group), group.size, kind)
        end
        others = Cache::Janitor.old_compilers
        old_mb = others.sum { |dir| Cache::Store.tree_bytes(dir) } >> 20
        puts format("%6d MB  %5d  compiled compilers that older zr versions kept", old_mb, others.size)
        puts format("%6d MB  %5d  in all, in %s", Cache::Janitor.megabytes(files), files.size, Paths.cache)
      when "clean"
        all = args.include?("--all")
        sizes = Cache::Janitor.all.to_h { |path| [path, Cache::Janitor.bytes([path])] }
        gone = all ? Cache::Janitor.clear : Cache::Janitor.prune
        others = Cache::Janitor.old_compilers
        freed = gone.sum { |path| sizes.fetch(path, 0) } + others.sum { |dir| Cache::Store.tree_bytes(dir) }
        others.each { |dir| Paths.remove(dir) }
        puts format("deleted %d file(s) and %d compiled compiler(s), %d MB", gone.size, others.size, freed >> 20)
      else usage_error("unknown cache command '#{verb}'", "cache")
      end
    end

    def help(command = nil)
      return puts(USAGE) if command.nil?

      usage_error("unknown command '#{command}'") unless HELP.key?(command)
      puts HELP.fetch(command)
    end

    # One line that says what is wrong, and where to find help.
    def usage_error(message, command = nil)
      warn "zr#{" #{command}" if command}: #{message}"
      warn "Run 'zr help#{" #{command}" if command}' for usage."
      exit 2
    end

    # The options and words of `run`, `build` or `machine`, as a Hash.
    # For `run`, every word after the input file goes to the program.
    def parse(command, args)
      opts = { args: [], link: [], gems: [] }
      until args.empty?
        word = args.shift
        if opts[:input] && command == "run"
          opts[:args] << word
          next
        end
        name, value = word.start_with?("--") && word.include?("=") ? word.split("=", 2) : [word, nil]
        case name
        when "--" then opts[:input] ? opts[:args].concat(args.shift(args.size)) : (opts[:input] = args.shift)
        when "-h", "--help"
          help(command)
          exit
        when "-o", "--output" then opts[:output] = value || args.shift || usage_error("#{name} needs a path", command)
        when "--emit" then opts[:emit] = value || args.shift || usage_error("--emit needs a kind", command)
        when "--target" then opts[:triple] = value || args.shift || usage_error("--target needs a triple", command)
        when "--path-root" then opts[:root] = value || args.shift || usage_error("--path-root needs a directory", command)
        when "--link" then opts[:link] << (value || args.shift || usage_error("--link needs an argument", command))
        when "--gem" then opts[:gems] << gem_flag(value || args.shift, command)
        when "--print-gems" then opts[:print_gems] = true
        when "--allow-runtime-require" then opts[:runtime_require] = true
        when "--gemfile" then opts[:gemfile] = value || args.shift || usage_error("--gemfile needs a path", command)
        when /\A-./ then usage_error("unknown option '#{word}'", command)
        else
          opts[:input] ? opts[:args] << word : opts[:input] = word
        end
      end
      check(command, opts)
    end

    # `--gem NAME=VERSION` or `--gem NAME=DIR`, as [name, value].
    def gem_flag(word, command)
      name, value = word.to_s.split("=", 2)
      if value.to_s.empty? || !name.match?(/\A[\w.-]+\z/)
        usage_error("--gem needs <name>=<version> or <name>=<dir>, for example --gem csv=3.3.6", command)
      end
      [name, value]
    end

    # The gems that a compile reads before zr's standard library: the
    # `--gem` flags, then the Gemfile.lock of `--gemfile` or
    # BUNDLE_GEMFILE (lib/zr/gem_set.rb).
    def gem_set(opts)
      require_relative "gem_set"
      GemSet.resolve(opts[:gems], gemfile: opts[:gemfile])
    rescue GemSet::Unresolved => e
      abort "zr: #{e.message}"
    end

    def check(command, opts)
      return check_gems(opts) if command == "gems"

      usage_error("missing <file.rb>", command) unless opts[:input]
      usage_error("unknown --emit '#{opts[:emit]}'; use binary, obj or wasm", command) if opts[:emit] && !EMITS.key?(opts[:emit])
      usage_error("--path-root needs an absolute path", command) if opts[:root] && !opts[:root].start_with?("/")
      if command == "machine" && (!opts[:gems].empty? || opts[:gemfile])
        usage_error("--gem and --gemfile do not apply; a machine file requires nothing", command)
      end
      usage_error("--print-gems applies only to 'zr build'", command) if opts[:print_gems] && command != "build"
      if command == "run"
        usage_error("-o does not apply; use 'zr build' to keep the output", command) if opts[:output]
        usage_error("cannot run an object file; use 'zr build --emit obj'", command) if opts[:emit] == "obj"
      else
        usage_error("missing -o <path>", command) unless opts[:output]
        dir = File.dirname(opts[:output])
        usage_error("-o #{opts[:output]}: the directory #{dir} does not exist", command) unless File.directory?(dir)
        usage_error("unexpected argument '#{opts[:args].first}'", command) unless opts[:args].empty?
      end
      opts[:emit] = EMITS[opts[:emit]]
      opts
    end

    # `zr gems` takes the options that choose the gems, and at most one file.
    def check_gems(opts)
      usage_error("-o does not apply", "gems") if opts[:output]
      usage_error("unexpected argument '#{opts[:args].first}'", "gems") unless opts[:args].empty?
      opts[:emit] = EMITS[opts[:emit]]
      opts
    end

    # `run`, `build` or `machine`, and its arguments.
    def compile(command, args)
      opts = parse(command, args)
      pinned!
      input = opts[:input]
      abort "zr: no such file: #{input}" unless File.file?(input)
      gems = gem_set(opts) unless command == "machine"

      target = target_for(opts[:triple], opts[:emit], command)
      emit = opts[:emit] || ("wasm" if target.outputs == [:wasm])
      usage_error("--link applies only to a native binary", command) if emit && !opts[:link].empty?
      refuse(input, command, emit, target, chosen: !opts[:triple].nil?)
      wasmtime! if command == "run" && emit == "wasm"

      Paths.root = opts[:root]
      link = Config.current.link + opts[:link]
      cache = @missed || kept_run(input, target, link, opts[:args], gems) if command == "run" && emit.nil?
      require_relative "runtime"
      require_relative "native/build"
      # Under ruby, lib/zr/prism.rb turns the parse cache on. A compiled
      # compiler turns it on here. A program that calls eval includes the
      # same files but never comes here, so it never writes to the cache.
      require_relative "cache/parse" unless HOSTED
      if command == "run" && emit.nil? && Cache::Run.wanted?
        cache ||= Cache::Run.new(input, target: target, digest: Zr.runtime(target).digest, link: link, gems: gems)
      end
      program = lower(input, command, target, assemble: emit.nil?, gem_set: gems, gate: !opts[:runtime_require])
      status = Paths.tmpdir("zr-build-") do |work|
        out = command == "run" ? File.join(work, "program") : File.expand_path(opts[:output])
        case emit
        when "obj" then object(program, out, target)
        when "wasm" then wasm(program, out, command, opts[:args])
        else native(program, out, work, command, opts[:args], target, link: link, cache: cache)
        end
      end
      if opts[:print_gems]
        require_relative "gems_command"
        print GemsCommand.table(program.gems)
      end
      require_relative "cache/janitor"
      Cache::Janitor.trim
      exit_as(status) if status.is_a?(Process::Status)
    end

    # `zr run --emit wasm` runs the module with wasmtime. Without it, stop
    # before the build.
    def wasmtime!
      require_relative "doctor"
      return if Doctor.which("wasmtime")

      abort "zr: zr run --emit wasm needs wasmtime, and it is not on the PATH. Install it from https://wasmtime.dev, " \
            "or use 'zr build --emit wasm' to write the module only."
    end

    # The end of `zr run`, once the build is gone: the program's status.
    # A signal that stopped the program stops zr too, so the shell sees
    # the status that ruby gives when the signal stops it.
    def exit_as(status)
      exit(status.exitstatus) unless status.signaled?

      begin
        Signal.trap(status.termsig, "SYSTEM_DEFAULT")
      rescue ArgumentError
        # ruby keeps SIGSEGV, SIGBUS, SIGILL, SIGFPE and SIGVTALRM for
        # itself, and its own handler would print a ruby bug report. The
        # C library's `signal` sets the default action again. Without
        # Fiddle (a zr binary), zr exits with the status that a shell
        # gives for the signal.
        exit(128 + status.termsig) unless default_action!(status.termsig)
      end
      Process.kill(status.termsig, Process.pid)
      # Only a signal that does not stop a process by default comes here.
      sleep 1
      exit(128 + status.termsig)
    end

    # `signal(signo, SIG_DFL)` through Fiddle. Returns whether it was set.
    def default_action!(signo)
      require "fiddle"
      set = ::Fiddle::Function.new(::Fiddle::Handle::DEFAULT["signal"], [::Fiddle::TYPE_INT, ::Fiddle::TYPE_VOIDP], ::Fiddle::TYPE_VOIDP)
      set.call(signo, 0)
      true
    rescue LoadError, StandardError
      false
    end

    # The target that `--target` gives. `--emit wasm` alone means
    # wasm32-wasi.
    def target_for(triple, emit, command)
      return emit == "wasm" ? Target::WASM32_WASI : Target.default unless triple

      Target.fetch(triple) || usage_error("unknown target '#{triple}'. The targets are #{Target.all.map(&:triple).join(", ")}", command)
    end

    # A table of each target, the outputs zr makes for it, and the
    # outputs that this host can make.
    def targets
      name = ->(output) { output == :native ? "binary" : output.to_s }
      rows = Target.all.map do |target|
        here = target.outputs.select { |output| target.refusal(output == :native ? nil : output.to_s).nil? }
        [target.triple, target.outputs.map(&name).join(", "), here.empty? ? "none" : here.map(&name).join(", ")]
      end
      [["TARGET", "OUTPUTS", "ON THIS HOST"], *rows].each do |row|
        puts format("%-22s %-18s %s", *row).rstrip
      end
    end

    # Refuses a build that this host cannot make for `target`, before the
    # compile starts. zr's own Mach-O linker builds an
    # aarch64-apple-darwin binary on any host, but only that host can run
    # it. A cross toolchain builds a binary that only its target host
    # runs.
    def refuse(input, verb, emit, target, chosen: true)
      why = target.refusal(emit)
      if why.nil? && verb == "run" && emit.nil? && !target.runs_here?
        why = "#{foreign(target, chosen)} To run the program here, use 'zr run --emit wasm #{input}'."
      end
      if why.nil? && verb == "build" && emit.nil? && !chosen && !target.runs_here?
        warn "zr: #{foreign(target, chosen)} Give --emit wasm for a module that runs here with wasmtime."
      end
      return unless why

      warn "zr: #{input}: #{why}"
      exit REFUSED
    end

    # The words for a native target that this host cannot run. `chosen`
    # is false when the build took the default target, not a --target.
    def foreign(target, chosen)
      what = "this computer cannot run #{target.triple} binaries."
      return what if chosen

      "#{what} zr builds one for #{TARGET_NAMES.fetch(target.triple, target.triple)}."
    end

    TARGET_NAMES = { "aarch64-apple-darwin" => "macOS on Apple Silicon" }.freeze

    # What `zr` prints when it refuses a program: the message, then for a
    # form of Ruby, the source line with a caret and the page that lists
    # what zr supports.
    def refusal_report(error)
      lines = ["zr: #{error.message}"]
      if error.form
        lines << error.excerpt if error.excerpt
        lines << "zr: #{Refused::DOCS} lists what zr supports"
      end
      lines.join("\n")
    end

    # The program that writes ruby's report of a syntax error. It loads
    # zr's own syntax_suggest (vendor/ruby) by its path, as a stock ruby
    # 4.0.7 has it: `api` first, so `core_ext` does not require it by name
    # (a second core_ext would wrap the message twice). ruby prints the
    # parse's warnings before the error, so the report has them too. It
    # exits 2 when the file parses.
    SYNTAX_REPORT = <<~'RUBY'
      syntax_suggest, input = ARGV
      require File.join(syntax_suggest, "api")
      require File.join(syntax_suggest, "core_ext")
      warned = +""
      sink = Object.new
      sink.define_singleton_method(:write) { |*parts| warned << parts.join }
      $stderr = sink
      begin
        RubyVM::InstructionSequence.compile_file(input)
      rescue SyntaxError => e
        error = e
      ensure
        # syntax_suggest writes to $stderr as it builds the message.
        $stderr = STDERR
      end
      exit 2 unless error
      print warned, input, ": ", error.detailed_message(highlight: false), "\n"
    RUBY

    # ruby's report for `input`, which does not parse, or nil when it
    # parses (then a file that it requires did not). The host ruby writes
    # it, without gems, so no other version of syntax_suggest is loaded.
    def syntax_report(input)
      require_relative "libraries"
      argv = [Config.current.host_ruby, "--disable-gems", "-e", SYNTAX_REPORT, File.join(Libraries.root, "syntax_suggest"), input]
      out = IO.popen(argv, err: File::NULL, &:read)
      $?.success? ? out : nil
    end

    # A binary's functions are assembled as they are lowered, so the IR of
    # a large program is never all in memory at once (`Native::Build.lower`).
    def lower(input, verb, target, assemble: false, gem_set: nil, gate: false)
      source = File.read(input)
      return Machine.compile(source, input) if verb == "machine"
      return Zr.program(source, input, target: target, gem_set: gem_set, gate: gate) unless assemble

      Native::Build.lower(source, input, target: target, sources: verb == "run", gem_set: gem_set, gate: gate)
    rescue Hir::Missing => e
      abort "zr: #{e.message}"
    rescue Refused => e
      warn refusal_report(e)
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
      report = syntax_report(input)
      unless report
        warn "zr: a required file does not parse: #{e.message.lines.first.chomp}"
        exit REFUSED
      end
      warn "zr: warning: #{input} does not parse. The output prints ruby's syntax error and exits with status 1" if verb == "build"
      Zr.program("$stderr.write(#{report.inspect})\nexit 1\n", input, target: target)
    end

    def object(program, out, target)
      why = if program.is_a?(Zr::Program)
              # The runtime's object goes into the cache, so the object
              # file at `out` is the only file that zr writes.
              Native::Build.runtime_object(program.runtime)
              Native::Build.object(program.functions, program.data, out, export: true, target: target)
            else
              functions, data, raw = program
              Native::Build.object(functions, data, out, raw: raw, export: true, target: target)
            end
      abort "zr: #{why}" if why
      nil
    end

    def wasm(program, out, verb, rest)
      why = if program.is_a?(Zr::Program)
              Native::Build.wasm_program(program, out)
            else
              functions, data, raw = program
              Native::Build.wasm(functions, data, out, raw: raw)
            end
      abort "zr: #{why}" if why
      return nil unless verb == "run"

      # The module can see the working directory, as a ruby program can.
      # `system`, not `exec`, so that the build directory goes away after
      # the run, as for a binary.
      interrupt = Signal.trap("INT") { nil }
      system("wasmtime", "run", "--dir", ".", out, *rest)
      Signal.trap("INT", interrupt)
      $?
    end

    def native(program, out, work, verb, rest, target, link: [], cache: nil)
      why = if program.is_a?(Zr::Program)
              Native::Build.program(program, out, work: work, link: link)
            else
              functions, data, raw = program
              Native::Build.binary(functions, data, out, work: work, raw: raw, target: target, link: link)
            end
      abort "zr: #{why}" if why
      return unless verb == "run"

      kept = cache&.keep(out, program, work) if program.is_a?(Zr::Program)
      return @served.call(kept || out, rest, kept.nil?) if @served

      run_binary(out, rest)
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
      return unless argv.first == "run" && !ENV.key?(Tune::ADDED) && !Zr.compiled?

      require_relative "cache/run"
      return unless Cache::Run.wanted?

      opts = parse("run", argv.drop(1))
      return if opts[:emit] || opts[:triple] || host_refusal || !File.file?(opts[:input])

      target = Target.default
      return unless target.runs_here? && target.refusal(nil).nil?

      Paths.root = opts[:root]
      # A set that does not resolve goes on to the build, which says why.
      gems = kept_gems(opts) or return
      digest = RuntimeSources.for(target).runtime_digest or return
      cache = Cache::Run.new(opts[:input], target: target, digest: digest, link: Config.current.link + opts[:link], gems: gems)
      kept = cache.hit
      exec(Tune.program_env, [kept, kept], *opts[:args]) if kept
      # The build keeps its binary here, with no second digest.
      @missed = cache
    end

    # The GemSet of a `zr run` before the build, or nil when it does not
    # resolve.
    def kept_gems(opts)
      require_relative "gem_set"
      GemSet.resolve(opts[:gems], gemfile: opts[:gemfile])
    rescue GemSet::Unresolved
      nil
    end

    # A program that ran before with the same sources runs from the run
    # cache, and zr exits as it does. This loads only the digests, not the
    # compiler. Returns the cache for the build otherwise, or nil when zr
    # needs a build to know the runtime's digest.
    def kept_run(input, target, link, args, gems)
      require_relative "cache/run"
      return nil unless Cache::Run.wanted?

      digest = RuntimeSources.for(target).runtime_digest or return nil
      cache = Cache::Run.new(input, target: target, digest: digest, link: link, gems: gems)
      kept = cache.hit
      exit_as(run_binary(kept, args)) if kept
      cache
    end

    # Runs a binary with the arguments after the program's path, and
    # returns its status. A Ctrl-C goes to the program, which decides what
    # to do with it; zr waits for the program to end.
    def run_binary(binary, rest)
      interrupt = Signal.trap("INT") { nil }
      # `[binary, binary]`: with no arguments, a lone string would be a
      # command for the shell.
      system(Tune.program_env, [binary, binary], *rest)
      Signal.trap("INT", interrupt)
      $?
    end
  end
end
