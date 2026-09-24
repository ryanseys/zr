# frozen_string_literal: true

require "rbconfig"
require_relative "version"
require_relative "paths"
require_relative "target"

module Zr
  # The `zr` command, and the only one: `exe/zr` in a checkout, and
  # the gem's binstub once it is installed. Everything the repository
  # itself needs -- the tests, the bootstrap, the benchmark bank, the
  # generated tables -- is a rake task rather than a command here.
  module CLI
    USAGE = <<~TEXT
      zr run <file.rb> [args]              compile a Ruby program with the zr runtime, and run it
      zr build <file.rb> -o <bin>          compile a Ruby program with the zr runtime
      zr machine <file.rb> -o <bin>        compile a kernel-dialect file alone
                   [--emit obj|wasm] [--target <triple>] [--path-root=<dir>]
      zr zr run|build|machine ...          the same three commands, by their older names
      zr targets                           the targets zr builds for, and what this host can do
      zr version                           print zr's version

      ZR_LINK picks the macOS linker: unset for zr's own, and cc for what
      it cannot link; `ruby` for zr's alone, which names what it cannot
      link; `cc` for the system linker.
      ZR_CACHE names the runtime cache.

      --path-root writes every path under zr's root or the directory the
      build runs in as <dir> plus the path below it, so two checkouts built
      with one root make the same bytes. A path given relative stays as given.

      ruby is the oracle: every corpus program carries ruby 4.0.6's recorded
      answer, and zr is held to it or refuses by name.
    TEXT

    # Status 3 is a refusal by name; the sweep tells it from a defect.
    REFUSED = 3

    module_function

    # A compile allocates in the tens of millions of objects, and how
    # often it stops for a major collection is decided by the collector's
    # malloc limits -- which ruby reads as it starts and never again. So
    # the only way to raise them for this process is to start `script`
    # again with them raised. Measured over the runtime's 4,733 functions:
    # 3.47 s against 3.17 s, and one major collection where there were
    # four. A child the script starts inherits them and does not do this
    # twice. `ZR_GC=0` leaves the collector as ruby set it.
    #
    # The compiler runs under YJIT unless ZR_YJIT=0: a cold runtime build
    # is mostly the compiler's own Ruby, which YJIT runs well.
    # The collector's tuning a build runs under: a compile allocates in
    # bursts, and ruby's default limits collect through every one.
    GC_ENV = { "RUBY_GC_MALLOC_LIMIT" => "64000000", "RUBY_GC_OLDMALLOC_LIMIT" => "128000000" }.freeze

    # A process that starts without the tuning starts again with it;
    # one started with it (a harness child) goes straight on. Only
    # CRuby's collector reads these limits, so only CRuby starts again:
    # the compiler compiled by zr is this same file, and its
    # `RbConfig.ruby` names zr's own interpreter (rt/ext/rbconfig.rb),
    # which is neither this process nor always a file that exists.
    def tune!(script)
      if ENV["ZR_GC"] != "0" && !ENV.key?("RUBY_GC_MALLOC_LIMIT") && cruby?
        ENV.update(GC_ENV)
        exec(RbConfig.ruby, script, *ARGV)
      end
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable) && ENV["ZR_YJIT"] != "0"
    end

    # Whether this compiler runs on CRuby, rather than as a program zr
    # compiled. A zr binary answers RUBY_ENGINE, RUBY_DESCRIPTION and
    # RubyVM as ruby 4.0.6 does, by design; its RbConfig names zr as the
    # interpreter (rt/ext/rbconfig.rb), which is the one fact that says so.
    def cruby? = RbConfig::CONFIG["ruby_install_name"] != "zr"

    # Why this compiler must not build on a ruby of `version`, or nil when
    # it is the ruby zr pins. Another ruby runs the compiler on a library
    # zr was never tested with, and its answers are not the ones zr is
    # held to.
    def host_refusal(version = RUBY_VERSION)
      return if version == RUBY

      "zr #{VERSION} builds on ruby #{RUBY}, the ruby .ruby-version pins; this is ruby #{version}"
    end

    # A build on any ruby but the pinned one stops here, by name, before
    # it reads the program.
    def pinned!(version = RUBY_VERSION)
      return unless (why = host_refusal(version))

      warn "zr: #{why}"
      exit REFUSED
    end

    # The usage text, with `extra` commands before the rest, on stderr.
    def usage(extra = "")
      warn(extra + USAGE)
      exit 2
    end

    # One named step of a long command, announced before it runs and
    # timed after: a command that says nothing until it ends cannot be
    # told from a hung one.
    def step(what)
      $stdout.sync = true
      print "#{what} ... "
      began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      answer = yield
      puts format("%.1fs", Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
      answer
    end

    def start(argv, extra: "")
      args = argv.dup
      case args.first
      when "run", "build", "machine" then compile(args, extra)
      when "zr" then compile(args.drop(1), extra)
      when "targets" then targets
      when "version", "--version", "-v" then puts "zr #{VERSION}"
      when "help", "-h", "--help"
        puts extra + USAGE
      else
        usage(extra)
      end
    end

    # `run`, `build` or `machine`, and its arguments.
    def compile(args, extra)
      verb = args.shift
      usage(extra) unless %w[run build machine].include?(verb)
      pinned!
      input = output = nil
      emit = nil
      triple = root = nil
      rest = []
      until args.empty?
        case (a = args.shift)
        when "-o" then output = args.shift or usage(extra)
        when "--emit" then emit = args.shift or usage(extra)
        when "--target" then triple = args.shift or usage(extra)
        when "--path-root" then root = args.shift or usage(extra)
        when /\A--path-root=(.+)\z/ then root = $1
        when /\A-/ then usage(extra)
        else
          if input then rest << a else input = a end
        end
      end
      usage(extra) unless input && (verb == "run" ? output.nil? : output)
      usage(extra) if verb != "run" && !rest.empty?
      usage(extra) unless [nil, "obj", "wasm"].include?(emit)
      usage(extra) unless root.nil? || root.start_with?("/")
      target = target_for(triple, emit, extra)
      emit ||= "wasm" if target.roads == [:wasm]
      refuse(input, verb, emit, target)

      require_relative "zr"
      require_relative "native/build"
      # Under ruby, lib/zr/prism.rb turns the parse cache on. A compiled
      # compiler turns it on here, where it builds: a program that evals
      # carries the same files and never comes here, so it never writes
      # a parse to the cache.
      require_relative "parse_cache" unless HOSTED
      Paths.root = root
      program = lower(input, verb, target, assemble: emit.nil?)
      Paths.scratch("zr-zr-") do |work|
        out = verb == "run" ? File.join(work, "program") : File.expand_path(output)
        case emit
        when "obj" then object(program, out, target)
        when "wasm" then wasm(program, out, verb, rest)
        else native(program, out, work, verb, rest, target)
        end
      end
    end

    # The target `--target` names; `--emit wasm` alone means wasm32-wasi.
    def target_for(triple, emit, extra)
      if triple
        target = Target.fetch(triple)
        return target if target

        warn "zr: no target #{triple}; `zr targets` names them"
        usage(extra)
      end
      emit == "wasm" ? Target::WASM32_WASI : Target.default
    end

    def targets
      Target.all.each do |target|
        roads = target.roads.map { |road| road == :native ? "binary" : road.to_s }
        can = %i[native obj wasm].select { |road| target.roads.include?(road) && target.refusal(road == :native ? nil : road.to_s).nil? }
        puts format("%-22s builds %-12s here: %s", target.triple, roads.empty? ? "nothing yet" : roads.join(", "),
                    can.empty? ? "nothing" : can.map { |road| road == :native ? "binary" : road.to_s }.join(", "))
      end
    end

    # A build this host cannot make for `target` is refused before the
    # compile starts. zr's own Mach-O linker builds an
    # aarch64-apple-darwin binary on any host, though only that host can
    # run it; a cross toolchain builds a binary that only its own host
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
    # a large program never stands all at once (`Native::Build.lower`).
    def lower(input, verb, target, assemble: false)
      source = File.read(input)
      return Machine.compile(source, input) if verb == "machine"
      return Zr.program(source, input, target: target) unless assemble

      Native::Build.lower(source, input, target: target)
    rescue Machine::Refused, Hir::Refused, Zr::Lower::Refused => e
      warn "zr: #{e.message}"
      exit REFUSED
    rescue Backend::Refused, Libraries::Unresolved => e
      abort "zr: #{e.message}"
    rescue SyntaxError => e
      # ruby reports a program that does not parse and exits 1, and so
      # does the binary, with ruby's own report. A required file that does
      # not parse raises as the require runs, which zr does not do yet.
      report = begin
        # ruby's report goes through syntax_suggest, which ruby's boot
        # loads and a process started with --disable-gems (a harness
        # child) does not. The copy is zr's own -- 3.0.0, as ruby 4.0.6
        # loads it -- and never the host's: `api` by its path first,
        # which spares `core_ext` its own require by name. Only CRuby
        # asks, and by a computed path, so the compiler zr compiles
        # carries none of it; there the report is the parser's.
        # A ruby that booted with gems has loaded it already, and a
        # second core_ext would wrap the message twice.
        if cruby? && !defined?(SyntaxSuggest.module_for_detailed_message)
          require_relative "libraries"
          syntax_suggest = File.join(Libraries.root, "syntax_suggest")
          require File.join(syntax_suggest, "api")
          require File.join(syntax_suggest, "core_ext")
        end
        # ruby prints the parse's warnings before it reports the error,
        # so they go into the report too.
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
              # The runtime's object lands in the cache beside it, so the
              # object road is the whole of what zr wrote.
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
      # The module sees the working directory, as a program ruby runs does.
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
