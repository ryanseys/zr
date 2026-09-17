# frozen_string_literal: true

require "rbconfig"
require_relative "version"
require_relative "paths"
require_relative "target"

module Ze0
  # The `ze0` command a gem user runs. The checkout's bin/ze0 adds the
  # commands that need the corpus and tools/, and hands the rest here.
  module CLI
    USAGE = <<~TEXT
      ze0 run <file.rb> [args]              compile a Ruby program with the zr runtime, and run it
      ze0 build <file.rb> -o <bin>          compile a Ruby program with the zr runtime
      ze0 machine <file.rb> -o <bin>        compile a kernel-dialect file alone
                   [--emit obj|wasm] [--target <triple>]
      ze0 zr run|build|machine ...          the same three commands, by their older names
      ze0 targets                           the targets ze0 builds for, and what this host can do
      ze0 version                           print ze0's version

      ZE0_LINK picks the linker: `ruby` for ze0's own Mach-O linker alone,
      which names what it cannot link; `cc` for the system linker; unset to
      take ze0's where it reaches and cc for a program that links the
      runtime as an object of its own.
      ZE0_CACHE names the runtime cache.

      ruby is the oracle: every corpus program carries ruby 4.0.6's recorded
      answer, and ze0 is held to it or refuses by name.
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
    # twice. `ZE0_GC=0` leaves the collector as ruby set it.
    #
    # The compiler runs under YJIT unless ZE0_YJIT=0: a cold runtime build
    # is mostly the compiler's own Ruby, which YJIT runs well.
    # The collector's tuning a build runs under: a compile allocates in
    # bursts, and ruby's default limits collect through every one.
    GC_ENV = { "RUBY_GC_MALLOC_LIMIT" => "64000000", "RUBY_GC_OLDMALLOC_LIMIT" => "128000000" }.freeze

    # A process that starts without the tuning starts again with it;
    # one started with it (a harness child) goes straight on.
    def tune!(script)
      if ENV["ZE0_GC"] != "0" && !ENV.key?("RUBY_GC_MALLOC_LIMIT")
        ENV.update(GC_ENV)
        exec(RbConfig.ruby, script, *ARGV)
      end
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable) && ENV["ZE0_YJIT"] != "0"
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
      when "version", "--version", "-v" then puts "ze0 #{VERSION}"
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
      input = output = nil
      emit = nil
      triple = nil
      rest = []
      until args.empty?
        case (a = args.shift)
        when "-o" then output = args.shift or usage(extra)
        when "--emit" then emit = args.shift or usage(extra)
        when "--target" then triple = args.shift or usage(extra)
        when /\A-/ then usage(extra)
        else
          if input then rest << a else input = a end
        end
      end
      usage(extra) unless input && (verb == "run" ? output.nil? : output)
      usage(extra) if verb != "run" && !rest.empty?
      usage(extra) unless [nil, "obj", "wasm"].include?(emit)
      target = target_for(triple, emit, extra)
      emit ||= "wasm" if target.roads == [:wasm]
      refuse(input, verb, emit, target)

      require "tmpdir"
      require_relative "zr"
      require_relative "native/build"
      program = lower(input, verb, target, assemble: emit.nil?)
      Dir.mktmpdir("ze0-zr-") do |work|
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

        warn "ze0: no target #{triple}; `ze0 targets` names them"
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
    # compile starts. `ZE0_LINK=ruby` builds with `Obj::MachO::Executable`
    # alone, which needs no `cc`, though only an aarch64-apple-darwin host
    # can run what it wrote. A cross toolchain builds a binary that only
    # its own host runs.
    def refuse(input, verb, emit, target)
      why = target.refusal(emit)
      if why.nil? && verb == "run" && emit.nil? && !target.native?
        why = "a #{target.triple} binary runs only on a #{target.triple} host; `ze0 build` writes one here"
      end
      return unless why
      return if emit.nil? && verb != "run" && ENV["ZE0_LINK"] == "ruby" && target.roads.include?(:native)

      warn "ze0: #{input}: #{why}"
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
      warn "ze0: #{e.message}"
      exit REFUSED
    rescue Backend::Refused => e
      abort "ze0: #{e.message}"
    rescue SyntaxError => e
      # ruby reports a program that does not parse and exits 1, and so
      # does the binary, with ruby's own report. A required file that does
      # not parse raises as the require runs, which ze0 does not do yet.
      report = begin
        # ruby's report goes through syntax_suggest, which ruby's boot
        # loads and a process started with --disable-gems (a harness
        # child) does not; rubygems first, so the bundled gem answers
        # and not the older copy under lib/ruby.
        begin
          require "rubygems"
          require "syntax_suggest/core_ext"
        rescue LoadError
          nil
        end
        RubyVM::InstructionSequence.compile_file(input)
        nil
      rescue SyntaxError => own
        "#{input}: #{own.detailed_message(highlight: false)}\n"
      end
      unless report
        warn "ze0: a required file does not parse: #{e.message.lines.first.chomp}"
        exit REFUSED
      end
      Zr.program("$stderr.write(#{report.inspect})\nexit 1\n", input, target: target)
    end

    def object(program, out, target)
      why = if program.is_a?(Zr::Program)
              # The runtime's object lands in the cache beside it, so the
              # object road is the whole of what ze0 wrote.
              Native::Build.runtime_object(program.runtime)
              Native::Build.object(program.functions, program.data, out, export: true, target: target)
            else
              functions, data, raw = program
              Native::Build.object(functions, data, out, raw: raw, export: true, target: target)
            end
      abort "ze0: #{why}" if why
      exit 0
    end

    def wasm(program, out, verb, rest)
      why = if program.is_a?(Zr::Program)
              Native::Build.wasm_program(program, out)
            else
              functions, data, raw = program
              Native::Build.wasm(functions, data, out, raw: raw)
            end
      abort "ze0: #{why}" if why
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
      abort "ze0: #{why}" if why
      return unless verb == "run"

      system(out, *rest)
      abort "ze0: the program died with signal #{$?.termsig}" if $?.signaled?
      exit($?.exitstatus)
    end
  end
end
