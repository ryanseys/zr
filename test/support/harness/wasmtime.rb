# frozen_string_literal: true

module Ze0
  module Harness
    # The one place the checks spell a `wasmtime` command, so every tier
    # runs a module the same way: the executable `WASMTIME` names, the
    # compiler the run asks for, and the bound on the module's memory.
    #
    # The checks compile under Winch, wasmtime's baseline compiler, and
    # not Cranelift, its optimising one. A test wants the answer and not
    # the speed, and a ze0 module is nearly all runtime -- 35 to 130 MB
    # that Cranelift compiles again for every program, since its cache
    # keys on the whole module's bytes. Measured on 2026-09-21, wasmtime
    # 48.0.2, this machine: a 35 MB module took 17.6 s of CPU under
    # Cranelift and 2.8 s under Winch; the 131 MB module that carries the
    # eval road, 70 s against 12 s. stdout, stderr and the exit status
    # were the same under both, on every module tried. `rake bench`
    # keeps Cranelift, since there the speed is the answer, and
    # `ZE0_WASM_COMPILER=cranelift` asks a tier for it.
    #
    # None of this reaches `lib`: `ze0 run` starts wasmtime as wasmtime
    # is, and these names are the checks' own.
    module Wasmtime
      COMPILERS = %w[winch cranelift].freeze

      module_function

      def executable = ENV.fetch("WASMTIME", "wasmtime")

      def compiler
        ENV.fetch("ZE0_WASM_COMPILER", "winch").tap do |name|
          raise ArgumentError, "ZE0_WASM_COMPILER is #{name}; wasmtime has #{COMPILERS.join(' and ')}" unless COMPILERS.include?(name)
        end
      end

      def memory = Integer(ENV.fetch("ZE0_WASM_MEMORY", 1 << 30))

      def installed? = system(executable, "--version", out: File::NULL, err: File::NULL)

      # The flags of a run: which compiler, and how much memory. Winch
      # compiles in a moment, so its output is not worth wasmtime's cache
      # (67 GB of it stood on one machine), and it compiles on one thread:
      # a tier runs a wasmtime in each of eight workers, and eight of
      # them each compiling on every core took a row of two seconds to
      # forty. One thread a row is 2.0 s of CPU against 3.0 s parallel,
      # and the rows keep to a core each. Cranelift keeps both, since it
      # runs one bench row at a time.
      def flags(compiler: self.compiler)
        own = compiler == "winch" ? ["-C", "cache=n", "-C", "parallel-compilation=n"] : []
        ["-C", "compiler=#{compiler}", *own, "-W", "max-memory-size=#{memory}"]
      end

      # `wasmtime run` of `module_path` with `args`, the directories in
      # `dirs` preopened (`{ "." => "." }` gives the guest the current
      # one at its own name) and `env` passed in by name.
      def run(module_path, *args, dirs: {}, env: {}, compiler: self.compiler)
        opened = dirs.flat_map { |host, guest| ["--dir", "#{host}::#{guest}"] }
        named = env.flat_map { |name, value| ["--env", "#{name}=#{value}"] }
        [executable, "run", *flags(compiler: compiler), *opened, *named, module_path, *args]
      end
    end
  end
end
