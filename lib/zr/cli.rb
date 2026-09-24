# frozen_string_literal: true

require "rbconfig"
require_relative "version"
require_relative "paths"
require_relative "flags"
require_relative "target"

module Zr
  # The `zr` command: `exe/zr` in a checkout, and the gem's executable
  # once it is installed. The repository's own tools (tests, bootstrap,
  # benchmarks, generated tables) are rake tasks.
  #
  # The parser is a small table, not OptionParser: optparse requires
  # `pp`, which calls eval, and a compiler that zr compiles would then
  # have to include eval support.
  module CLI
    USAGE = <<~TEXT
      Usage: zr <command> [options]

      Commands:
        run <file.rb> [args...]     compile a program, run it, then delete the build
        build <file.rb> -o <out>    compile a program to a binary, a WASI module or an object
        machine <file.rb> -o <out>  compile one machine-dialect file (for runtime work)
        targets                     list the targets, and what this host can build
        version                     print the version
        help [<command>]            print help for zr or for one command

      Exit status: 0 success; 1 error; 2 usage error; 3 zr does not support
      the program or the target. `zr run` exits with the program's status.
      Environment variables: docs/reference/environment-variables.md
    TEXT

    OUTPUT = "  -o, --output <path>    write the output to <path>\n"
    OPTIONS = <<~TEXT
      Options:
        --emit <kind>          binary (the default), obj, or wasm
        --target <triple>      build for <triple> (see `zr targets`)
        --path-root <dir>      write source paths in the output as <dir> plus the
                               path below zr's root or the working directory,
                               so that two checkouts make the same bytes
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

        #{OPTIONS.sub("Options:\n", "Options:\n#{OUTPUT}")}
      TEXT
      "machine" => <<~TEXT
        Usage: zr machine [options] <file.rb> -o <out>

        Compiles one file of the machine dialect (the typed Ruby that
        runtime/kernel is written in), without the zr runtime.

        #{OPTIONS.sub("Options:\n", "Options:\n#{OUTPUT}")}
      TEXT
    }.freeze

    COMPILE = HELP.keys.freeze
    EMITS = { "binary" => nil, "obj" => "obj", "wasm" => "wasm" }.freeze

    # Exit status 3: zr does not support the program or the target. The
    # test harness counts this separately from zr's defects.
    REFUSED = 3

    module_function

    # A compile allocates tens of millions of objects. Ruby reads the
    # collector's malloc limits only at startup, so a process without
    # them starts `script` again with them set (3.17 s against 3.47 s
    # for the runtime's 4,733 functions). With no `script` (a rake task),
    # the limits go only to the child processes. Only CRuby reads them.
    # `ZR_TUNE=0` keeps ruby's limits and leaves YJIT off.
    GC_ENV = { "RUBY_GC_MALLOC_LIMIT" => "64000000", "RUBY_GC_OLDMALLOC_LIMIT" => "128000000" }.freeze

    def tune!(script = nil)
      return unless Zr.flag?("ZR_TUNE", default: true)

      if !ENV.key?("RUBY_GC_MALLOC_LIMIT") && !Zr.compiled?
        ENV.update(GC_ENV)
        exec(RbConfig.ruby, script, *ARGV) if script
      end
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
    end

    # Why this compiler must not build on a ruby of `version`, or nil
    # when it is the ruby that zr pins. zr checks its output against that
    # one ruby only.
    def host_refusal(version = RUBY_VERSION)
      return if version == RUBY

      "zr #{VERSION} builds on ruby #{RUBY}, the ruby .ruby-version pins; this is ruby #{version}"
    end

    # Stops a build on any ruby but the pinned one, before it reads the
    # program.
    def pinned!(version = RUBY_VERSION)
      return unless (why = host_refusal(version))

      warn "zr: #{why}"
      exit REFUSED
    end

    def start(argv)
      args = argv.dup
      command = args.shift
      case command
      when *COMPILE then compile(command, args)
      when "targets" then targets
      when "version", "--version", "-v" then puts "zr #{VERSION}"
      when "help", "-h", "--help" then help(args.first)
      when nil
        warn USAGE
        exit 2
      else
        usage_error("unknown command '#{command}'")
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
      opts = { args: [] }
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
        when /\A-./ then usage_error("unknown option '#{word}'", command)
        else
          opts[:input] ? opts[:args] << word : opts[:input] = word
        end
      end
      check(command, opts)
    end

    def check(command, opts)
      usage_error("missing <file.rb>", command) unless opts[:input]
      usage_error("unknown --emit '#{opts[:emit]}'; use binary, obj or wasm", command) if opts[:emit] && !EMITS.key?(opts[:emit])
      usage_error("--path-root needs an absolute path", command) if opts[:root] && !opts[:root].start_with?("/")
      if command == "run"
        usage_error("-o does not apply; use 'zr build' to keep the output", command) if opts[:output]
        usage_error("cannot run an object file; use 'zr build --emit obj'", command) if opts[:emit] == "obj"
      else
        usage_error("missing -o <path>", command) unless opts[:output]
        usage_error("unexpected argument '#{opts[:args].first}'", command) unless opts[:args].empty?
      end
      opts[:emit] = EMITS[opts[:emit]]
      opts
    end

    # `run`, `build` or `machine`, and its arguments.
    def compile(command, args)
      opts = parse(command, args)
      pinned!
      input = opts[:input]
      abort "zr: no such file: #{input}" unless File.file?(input)

      target = target_for(opts[:triple], opts[:emit], command)
      emit = opts[:emit] || ("wasm" if target.outputs == [:wasm])
      refuse(input, command, emit, target)

      require_relative "runtime"
      require_relative "native/build"
      # Under ruby, lib/zr/prism.rb turns the parse cache on. A compiled
      # compiler turns it on here. A program that calls eval includes the
      # same files but never comes here, so it never writes to the cache.
      require_relative "parse_cache" unless HOSTED
      Paths.root = opts[:root]
      program = lower(input, command, target, assemble: emit.nil?)
      Paths.tmpdir("zr-build-") do |work|
        out = command == "run" ? File.join(work, "program") : File.expand_path(opts[:output])
        case emit
        when "obj" then object(program, out, target)
        when "wasm" then wasm(program, out, command, opts[:args])
        else native(program, out, work, command, opts[:args], target)
        end
      end
    end

    # The target that `--target` gives. `--emit wasm` alone means
    # wasm32-wasi.
    def target_for(triple, emit, command)
      return emit == "wasm" ? Target::WASM32_WASI : Target.default unless triple

      Target.fetch(triple) || usage_error("unknown target '#{triple}'; 'zr targets' lists them", command)
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
    def refuse(input, verb, emit, target)
      why = target.refusal(emit)
      if why.nil? && verb == "run" && emit.nil? && !target.native?
        why = "a #{target.triple} binary runs only on a #{target.triple} host; `zr build` writes one here"
      end
      return unless why

      warn "zr: #{input}: #{why}"
      exit REFUSED
    end

    # A binary's functions are assembled as they are lowered, so the IR of
    # a large program is never all in memory at once (`Native::Build.lower`).
    def lower(input, verb, target, assemble: false)
      source = File.read(input)
      return Machine.compile(source, input) if verb == "machine"
      return Zr.program(source, input, target: target) unless assemble

      Native::Build.lower(source, input, target: target)
    rescue Refused => e
      warn "zr: #{e.message}"
      exit REFUSED
    rescue Backend::Refused, Libraries::Unresolved => e
      abort "zr: #{e.message}"
    rescue SyntaxError => e
      # For a program that does not parse, ruby prints a report and exits
      # 1. The binary does the same, with ruby's own report. In ruby, a
      # required file that does not parse raises when the require runs.
      # zr does not support this, so it refuses.
      report = begin
        # ruby's report uses syntax_suggest. Ruby's boot loads it, but a
        # process started with --disable-gems (a harness child) does not.
        # Load zr's own copy (3.0.0, as ruby 4.0.6 loads), never the
        # host's. Load `api` by its path first, so `core_ext` does not
        # require it by name. Only CRuby runs this, with a computed path,
        # so the compiled compiler does not link it in and uses the
        # parser's report. If ruby booted with gems, syntax_suggest is
        # already loaded, and a second core_ext would wrap the message
        # twice.
        if !Zr.compiled? && !defined?(SyntaxSuggest.module_for_detailed_message)
          require_relative "libraries"
          syntax_suggest = File.join(Libraries.root, "syntax_suggest")
          require File.join(syntax_suggest, "api")
          require File.join(syntax_suggest, "core_ext")
        end
        # ruby prints the parse's warnings before it reports the error,
        # so the report includes them.
        warned = +""
        sink = Object.new
        sink.define_singleton_method(:write) { |*parts| warned << parts.join }
        was = $stderr
        $stderr = sink
        begin
          RubyVM::InstructionSequence.compile_file(input)
        ensure
          $stderr = was
        end
        nil
      rescue SyntaxError => own
        "#{warned}#{input}: #{own.detailed_message(highlight: false)}\n"
      end
      unless report
        warn "zr: a required file does not parse: #{e.message.lines.first.chomp}"
        exit REFUSED
      end
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
      exit 0
    end

    def wasm(program, out, verb, rest)
      why = if program.is_a?(Zr::Program)
              Native::Build.wasm_program(program, out)
            else
              functions, data, raw = program
              Native::Build.wasm(functions, data, out, raw: raw)
            end
      abort "zr: #{why}" if why
      # The module can see the working directory, as a ruby program can.
      exec("wasmtime", "run", "--dir", ".", out, *rest) if verb == "run"
      exit 0
    end

    def native(program, out, work, verb, rest, target)
      why = if program.is_a?(Zr::Program)
              Native::Build.program(program, out, work: work)
            else
              functions, data, raw = program
              Native::Build.binary(functions, data, out, work: work, raw: raw, target: target)
            end
      abort "zr: #{why}" if why
      return unless verb == "run"

      system(out, *rest)
      abort "zr: the program died with signal #{$?.termsig}" if $?.signaled?
      exit($?.exitstatus)
    end
  end
end
