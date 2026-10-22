# frozen_string_literal: true

require "digest/sha2"
require "etc"
require "fileutils"
require "stringio"
require_relative "../workers"
require_relative "child"
require_relative "../../../lib/zr/paths"
require_relative "../../../lib/zr/backend/wasm"
require_relative "../../../lib/zr/native/parallel"

module Zr
  module Harness
    # The only place where the tests make a `wasmtime` command, so every
    # tier runs a module the same way. It sets the executable (from
    # `WASMTIME`), the compiler, and the memory limit of the module.
    #
    # The tests use Winch, wasmtime's baseline compiler, not Cranelift, its
    # optimizing compiler. A test needs the output, not the speed. A zr
    # module is almost all runtime, and Cranelift compiles it again for
    # each program, because its cache key is the whole module; Winch
    # compiles it some times faster, with the same output and exit status.
    # `zr-dev bench` uses Cranelift, because there the speed is the result.
    # `ZR_TEST_WASM_COMPILER=cranelift` selects it for a tier.
    #
    # A program test builds a program module (`ZR_TEST_WASM_SPLIT`, on
    # unless 0): the runtime is a module of its own, which wasmtime
    # compiles once for each runtime (`runtime`) and preloads for each
    # program, so a test compiles only its program's code. A whole module
    # sent the 64 MB of the runtime's code through wasmtime for each test.
    # The cli tier builds with `zr build`, which writes a whole module, so
    # the default stays tested.
    #
    # `lib` does not use this: `zr run` starts wasmtime with its defaults.
    module Wasmtime
      COMPILERS = %w[winch cranelift].freeze
      # The wasmtime that the tests are run with: CI installs this version
      # (`WASMTIME_VERSION` in each workflow; layout_test checks that they
      # agree).
      VERSION = "50.0.0"
      # The bounds of one `wasmtime compile`, summed over its process
      # group (Child.run): a compile of a runtime with eval support peaked
      # at 4.8 GB with Winch and 5.1 GB with Cranelift. A compile of a
      # module past BIG_BYTES also takes a lock of the cache, so one runs
      # at a time: the cli tier compiled one in each worker, and without a
      # bound they took all of the machine's memory.
      # The bound is a third of the machine, at most 6 GB, so a compile
      # leaves room for the workers and the system.
      COMPILE_MB = Integer(ENV.fetch("ZR_TEST_COMPILE_MB") { [6144, (Native::Parallel.machine_bytes >> 20) / 3].min })
      COMPILE_SECONDS = Integer(ENV.fetch("ZR_TEST_COMPILE_SECONDS", "900"))
      BIG_BYTES = 32 << 20
      # The threads of a compile of a module past BIG_BYTES. The memory of a
      # compile grows with its threads, and wasmtime's pool (rayon) starts
      # one on each core: the runtime with eval support peaked at 5.1 GB
      # on 12. Each thread holds the functions that it compiles.
      COMPILE_THREADS = Integer(ENV.fetch("ZR_TEST_COMPILE_THREADS", "2"))

      module_function

      def executable = ENV.fetch("WASMTIME", "wasmtime")

      def compiler = named_compiler("ZR_TEST_WASM_COMPILER", "winch")

      # The compiler of a split run: the runtime and the program module
      # (one engine takes code of one compiler). Cranelift compiles the
      # runtime once for the tier (6 s on 12 cores, 18 s with eval
      # support, against 1 s and 3 s for Winch), and its code runs faster:
      # a program with eval took 0.26 s, against 0.41 s.
      def split_compiler = named_compiler("ZR_TEST_WASM_SPLIT_COMPILER", "cranelift")

      def named_compiler(variable, default)
        ENV.fetch(variable, default).tap do |name|
          raise ArgumentError, "#{variable} is #{name}; wasmtime has #{COMPILERS.join(" and ")}" unless COMPILERS.include?(name)
        end
      end

      # A module's address space: all 4 GiB of wasm32, as `zr run` and
      # wasmtime give it. Pages that a module never touches are not
      # resident, and the run's memory limit (Child::RUN_MB) bounds the
      # pages that it does; the heap's arenas each take a 4 MiB window of
      # the address space (zr_arena_of).
      def memory = Integer(ENV.fetch("ZR_TEST_WASM_MEMORY", 1 << 32))

      def installed? = system(executable, "--version", out: File::NULL, err: File::NULL)

      def split? = ENV.fetch("ZR_TEST_WASM_SPLIT", "1") != "0"

      # Where a program build writes its runtime module: one file for each
      # runtime, which every test of the run shares.
      def split_dir = File.join(Paths.cache, "wasm-split")

      # The flags of a run: the compiler and the memory limit. The tests
      # turn off wasmtime's cache: each test's module is new, and the cache
      # grew to 67 GB on one machine (the runtime module's compile is kept
      # by `runtime`). A compile runs on one thread when the workers fill
      # the cores: a tier runs wasmtime in each of eight workers, and eight
      # parallel compiles on all cores made a 2 s test take 40 s. One
      # thread uses 2.0 s of CPU against 3.0 s in parallel. Where the
      # workers leave half of the cores free (a CI runner: 2 workers on 4
      # cores), a compile takes them: a cli program's module with eval
      # support took 28 s on one thread.
      #
      # A test needs the output, not fast code, so Cranelift does not
      # optimize (`opt-level=0`, or `ZR_TEST_WASM_OPT_LEVEL`; `zr-dev bench`
      # sets 2), and no code keeps the map from native addresses to wasm
      # offsets (`address-map=n`): both cut the memory and time of a
      # compile. A trap still says "wasm trap: ".
      def flags(compiler: self.compiler)
        ["-C", "compiler=#{compiler}", "-C", "cache=n", "-C", "parallel-compilation=#{spare_cores? ? "y" : "n"}",
         "-O", "opt-level=#{opt_level}", "-D", "address-map=n", "-W", "max-memory-size=#{memory}"]
      end

      def opt_level = ENV.fetch("ZR_TEST_WASM_OPT_LEVEL", "0")

      def spare_cores? = Etc.nprocessors >= 2 * Test::Workers.size

      # The `wasmtime run` command for `module_path` with `args`. It
      # preopens the directories in `dirs` (`{ "." => "." }` gives the
      # guest the current directory with the same name) and passes each
      # variable in `env` by name. `argv0` gives the program name that the
      # guest sees, for a precompiled module with a different file name.
      # `preload` is the compiled runtime module that a program module
      # imports (`runtime`).
      def run(module_path, *args, dirs: {}, env: {}, compiler: self.compiler, argv0: nil, preload: nil)
        opened = dirs.flat_map { |host, guest| ["--dir", "#{host}::#{guest}"] }
        named = env.flat_map { |name, value| ["--env", "#{name}=#{value}"] }
        precompiled = module_path.end_with?(".cwasm") || preload ? ["--allow-precompiled"] : []
        linked = preload ? ["--preload", "#{Backend::Wasm::Codegen::RUNTIME}=#{preload}"] : []
        [executable, "run", *flags(compiler: compiler), *precompiled, *linked, *(["--argv0", argv0] if argv0), *opened, *named,
         module_path, *args]
      end

      # The compiled form of the runtime module at `path`, compiled one
      # time for each runtime, wasmtime and set of flags, in the cache
      # (`<cache>/wasmtime`). Each worker of a tier asks for it, so the
      # first compiles it under a lock and the others wait. Returns nil
      # when the compile fails.
      # The key leaves out `parallel-compilation`: the output is the same
      # with it or without it, and MT_CPU changes it. A process keeps the
      # answer for each file by its size and time: the hash of a 68 MB
      # runtime module took 50 to 100 ms, once for each test.
      def runtime(path, compiler: self.compiler)
        stat = File.stat(path)
        # rubocop:disable ThreadSafety/ClassInstanceVariable -- a worker is a forked process with one thread
        known = (@runtimes ||= {})[[path, stat.size, stat.mtime, compiler]]
        return known if known && File.exist?(known)

        @runtimes[[path, stat.size, stat.mtime, compiler]] = compiled_runtime(path, compiler)
        # rubocop:enable ThreadSafety/ClassInstanceVariable
      end

      def compiled_runtime(path, compiler)
        kept = flags(compiler: compiler).reject { |flag| flag.start_with?("parallel-compilation=") }
        key = Digest::SHA256.hexdigest([Digest::SHA256.file(path).hexdigest, VERSION, *kept].join("\n"))
        dir = File.join(Paths.cache, "wasmtime")
        out = File.join(dir, "#{key}.cwasm")
        return out if File.exist?(out)

        FileUtils.mkdir_p(dir)
        File.open("#{out}.lock", File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          next if File.exist?(out)

          draft = "#{out}.#{Process.pid}"
          compiled?(path, draft, compiler: compiler) ? File.rename(draft, out) : FileUtils.rm_f(draft)
        end
        File.exist?(out) ? out : nil
      end

      # The file name of the runtime module that the program module at
      # `path` imports (Backend::Wasm.runtime_of), or nil for a whole
      # module. It reads only the sections' headers, and the custom ones.
      def runtime_of(path)
        File.open(path, "rb") do |io|
          io.seek(8)
          until io.eof?
            id = io.readbyte
            size = leb(io)
            next io.seek(size, IO::SEEK_CUR) unless id.zero?

            section = StringIO.new(io.read(size).to_s)
            name = section.read(leb(section))
            return section.read if name == Backend::Wasm::Codegen::RUNTIME_SECTION
          end
        end
        nil
      end

      def leb(io)
        value = 0
        shift = 0
        loop do
          byte = io.readbyte
          value |= (byte & 0x7F) << shift
          return value if byte < 0x80

          shift += 7
        end
      end

      # Compiles `module_path` to `<module_path>.cwasm` and returns that
      # path, or nil when the compile fails (a run of the module then
      # reports why). The compile of a module with eval support takes some
      # times the memory of its run. A test limits the memory of the run,
      # so it must not count the compile.
      def precompile(module_path, compiler: self.compiler)
        out = "#{module_path}.cwasm"
        compiled?(module_path, out, compiler: compiler) ? out : nil
      end

      # Whether `wasmtime compile` of `path` to `out` finished inside
      # COMPILE_SECONDS and COMPILE_MB.
      #
      # A big module compiles on COMPILE_THREADS threads, at background
      # priority on macOS (`taskpolicy -b`), so the machine stays usable.
      def compiled?(path, out, compiler: self.compiler)
        big = File.size(path) > BIG_BYTES
        argv = [*(background if big), executable, "compile", *flags(compiler: compiler), "-o", out, path]
        env = big ? { "RAYON_NUM_THREADS" => COMPILE_THREADS.to_s } : {}
        one_at_a_time(big) do
          answer, = Child.run(argv, cwd: Dir.pwd, seconds: COMPILE_SECONDS, megabytes: COMPILE_MB, env: env)
          answer.code.zero?
        end
      end

      # The prefix of a command that runs at background priority, or nil.
      def background
        %w[/usr/sbin/taskpolicy -b] if RUBY_PLATFORM.include?("darwin") && File.executable?("/usr/sbin/taskpolicy")
      end

      # Runs the block, under the cache's compile lock when `locked`.
      def one_at_a_time(locked)
        return yield unless locked

        dir = File.join(Paths.cache, "wasmtime")
        FileUtils.mkdir_p(dir)
        File.open(File.join(dir, "compile.lock"), File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          wait_for_memory
          yield
        end
      end

      # How long a big compile waits for the memory of its bound, in
      # seconds, and how often it looks.
      MEMORY_WAIT = 600
      MEMORY_LOOK = 2

      # Waits, up to MEMORY_WAIT, while the system has less than an eighth
      # of the machine free (2 GB of 16): a compile that starts then pushes
      # the machine into swap. A laptop with its usual programs open has
      # about a quarter free. After the wait the compile starts anyway, and
      # its own bound (COMPILE_MB) stops it.
      def wait_for_memory
        deadline = Timing.now + MEMORY_WAIT
        low = Native::Parallel.machine_bytes / 8
        while (free = Native::Parallel.available_bytes) && free < low && Timing.now < deadline
          sleep MEMORY_LOOK
        end
      end
    end
  end
end
