# frozen_string_literal: true

module Zr
  module Harness
    # The only place where the tests make a `wasmtime` command, so every
    # tier runs a module the same way. It sets the executable (from
    # `WASMTIME`), the compiler, and the memory limit of the module.
    #
    # The tests use Winch, wasmtime's baseline compiler, not Cranelift, its
    # optimizing compiler. A test needs the output, not the speed. A zr
    # module is almost all runtime (35 to 130 MB), and Cranelift compiles
    # it again for each program, because its cache key is the whole
    # module. With wasmtime 48.0.2, a 35 MB module took 17.6 s of CPU under
    # Cranelift and 2.8 s under Winch. The 131 MB module that includes eval
    # support took 70 s and 12 s. The output and exit status were the same.
    # `zr-dev bench` uses Cranelift, because there the speed is the result.
    # `ZR_TEST_WASM_COMPILER=cranelift` selects it for a tier.
    #
    # `lib` does not use this: `zr run` starts wasmtime with its defaults.
    module Wasmtime
      COMPILERS = %w[winch cranelift].freeze
      # The wasmtime that the tests are run with: CI installs this version
      # (`WASMTIME_VERSION` in each workflow; layout_test checks that they
      # agree).
      VERSION = "49.0.2"

      module_function

      def executable = ENV.fetch("WASMTIME", "wasmtime")

      def compiler
        ENV.fetch("ZR_TEST_WASM_COMPILER", "winch").tap do |name|
          raise ArgumentError, "ZR_TEST_WASM_COMPILER is #{name}; wasmtime has #{COMPILERS.join(" and ")}" unless COMPILERS.include?(name)
        end
      end

      def memory = Integer(ENV.fetch("ZR_TEST_WASM_MEMORY", 1 << 30))

      def installed? = system(executable, "--version", out: File::NULL, err: File::NULL)

      # The flags of a run: the compiler and the memory limit. Winch
      # compiles quickly, so the tests turn off wasmtime's cache (it grew
      # to 67 GB on one machine). Winch also compiles on one thread: a
      # tier runs wasmtime in each of eight workers, and eight parallel
      # compiles on all cores made a 2 s test take 40 s. One thread uses
      # 2.0 s of CPU against 3.0 s in parallel, and each test keeps to one
      # core. Cranelift keeps both, because a benchmark runs one at a time.
      def flags(compiler: self.compiler)
        own = compiler == "winch" ? ["-C", "cache=n", "-C", "parallel-compilation=n"] : []
        ["-C", "compiler=#{compiler}", *own, "-W", "max-memory-size=#{memory}"]
      end

      # The `wasmtime run` command for `module_path` with `args`. It
      # preopens the directories in `dirs` (`{ "." => "." }` gives the
      # guest the current directory with the same name) and passes each
      # variable in `env` by name. `argv0` gives the program name that the
      # guest sees, for a precompiled module with a different file name.
      def run(module_path, *args, dirs: {}, env: {}, compiler: self.compiler, argv0: nil)
        opened = dirs.flat_map { |host, guest| ["--dir", "#{host}::#{guest}"] }
        named = env.flat_map { |name, value| ["--env", "#{name}=#{value}"] }
        precompiled = module_path.end_with?(".cwasm") ? ["--allow-precompiled"] : []
        [executable, "run", *flags(compiler: compiler), *precompiled, *(["--argv0", argv0] if argv0), *opened, *named,
         module_path, *args]
      end

      # Compiles `module_path` to `<module_path>.cwasm` and returns that
      # path, or nil when the compile fails (a run of the module then
      # reports why). Winch uses 3.3 GB to compile a 157 MB module with
      # eval support, and the run of that module uses 0.5 GB. A test
      # limits the memory of the run, so it must not count the compile.
      def precompile(module_path, compiler: self.compiler)
        out = "#{module_path}.cwasm"
        ok = system(executable, "compile", *flags(compiler: compiler), "-o", out, module_path,
                    out: File::NULL, err: File::NULL)
        ok ? out : nil
      end
    end
  end
end
