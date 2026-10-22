# frozen_string_literal: true
# zr-test: runtime
# zr-test: on wasm

require "test_helper"
require_relative "../../lib/zr/machine/lower"
require_relative "../../lib/zr/native/build"
require_relative "../../test/native/fixtures"
require "support/runtime_programs"

# The wasm target: every hand-written IR program, every kernel-subset
# program that refers to no raw function, and every kernel core becomes
# one WASI module, and wasmtime prints what the native binary prints.
#
# All wasm tests are here, so a failure identifies the wasm backend and
# nothing else. The same programs go through the aarch64 backend in
# `native_test.rb`, `machine_test.rb` and `runtime_test.rb`.
class WasmTest < Minitest::Test
  def run_module(wasm, expected, *, status: 0)
    skip "wasmtime is not installed" unless Checks.wasmtime?

    answer = Checks.run(Zr::Harness::Wasmtime.run(wasm, *), merge: true)
    refute Checks.killed(answer), "wasmtime was killed at #{Checks.killed(answer)}: #{answer.stdout}"
    assert_equal status, answer.code, "wasmtime exited #{answer.code}: #{answer.stdout}"
    assert_equal expected, answer.stdout
  end

  Zr::Native::Fixtures::NAMES.each do |name|
    define_method("test_native_#{name}") do
      functions, data = Zr::Native::Fixtures.build(name)
      Dir.mktmpdir("zr-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Zr::Native::Build.wasm(functions, data, wasm)
        run_module(wasm, File.binread(File.join(ROOT, "test/native/#{name}.out")))
      end
    end
  end

  # Every hand-written module passes the validator of the specification,
  # which checks types that wasmtime can accept anyway. A value that the
  # backend typed differently from the IR shows here first.
  def test_the_modules_validate
    skip "wasm-tools is not installed" unless system("wasm-tools", "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir("zr-wasm-") do |dir|
      Zr::Native::Fixtures::NAMES.each do |name|
        functions, data = Zr::Native::Fixtures.build(name)
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Zr::Native::Build.wasm(functions, data, wasm)
        report = IO.popen(["wasm-tools", "validate", wasm], err: %i[child out], &:read)
        assert_predicate $?, :success?, "#{name}: #{report}"
      end
    end
  end

  # A kernel import that gives its wasm module reaches the host's own
  # call, and a native build refuses it with a message that gives the name.
  IMPORTED = <<~RUBY
    module Zr::Kern
      module Libc
        #: (i32, i32, i32, i32) -> i32
        def self.fd_write(i1, i2, i3, i4) = Machine.import(from: "wasi_snapshot_preview1")
      end

      #: (i32, ptr) -> i32
      def main(argc, argv)
        iov = Machine.slot(16)
        Machine.store32(iov, 0, Machine.i32(Machine.bytes("hi\n")))
        Machine.store32(iov, 4, Machine.i32(3))
        Libc.fd_write(Machine.i32(1), Machine.i32(iov), Machine.i32(1), Machine.i32(iov + 8))
        0
      end
    end
  RUBY

  def test_an_import_from_a_wasm_module
    functions, data = Zr::Machine.compile(IMPORTED, "imported.rb")
    Dir.mktmpdir("zr-wasm-") do |dir|
      wasm = File.join(dir, "imported.wasm")
      assert_nil Zr::Native::Build.wasm(functions, data, wasm)
      run_module(wasm, "hi\n")
      assert_equal "fd_write is a wasm import from wasi_snapshot_preview1, which no native link has",
                   Zr::Native::Build.binary(functions, data, File.join(dir, "imported"), work: dir)
    end
  end

  # A malloc that the memory cannot grow for gives 0, as libc's does, so
  # `zr_xmalloc` ends the program with ruby's message. It must not give an
  # address past the memory's end, where the first write traps far from
  # the cause.
  EXHAUSTED = <<~RUBY
    module Zr::Kern
      module Libc
        #: (word) -> ptr
        def self.malloc(n) = Machine.import
        #: (i32, ptr, word) -> word
        def self.write(i, p, n) = Machine.import
      end

      #: (i32, ptr) -> i32
      def main(argc, argv)
        i = 0
        while i < 64
          p = Libc.malloc(1048576)
          if p == 0
            Libc.write(Machine.i32(1), Machine.bytes("no memory\\n"), 10)
            return 0
          end
          Machine.store64(p + 1048568, 0, 1)
          i += 1
        end
        Libc.write(Machine.i32(1), Machine.bytes("all given\\n"), 10)
        0
      end
    end
  RUBY

  def test_a_malloc_past_the_memory_limit_gives_zero
    functions, data = Zr::Machine.compile(EXHAUSTED, "exhausted.rb")
    Dir.mktmpdir("zr-wasm-") do |dir|
      wasm = File.join(dir, "exhausted.wasm")
      assert_nil Zr::Native::Build.wasm(functions, data, wasm)
      with_env("ZR_TEST_WASM_MEMORY" => (16 << 20).to_s) { run_module(wasm, "no memory\n") }
    end
  end

  # The wasi layer's allocator (kernel/os/wasi/malloc.rb) over the heap's
  # bump: a freed block serves the next request of its class, a class is
  # at most a quarter larger than its request, a block of posix_memalign
  # is cut at its alignment, a small block of malloc takes the gap before
  # it, and a freed aligned block serves the next posix_memalign.
  ALLOCATOR = <<~RUBY
    module Zr::Kern
      module Libc
        #: (word) -> word
        def self.zr_wasm_sbrk(n) = Machine.import
        #: (ptr, ptr, word) -> ptr
        def self.memmove(p1, p2, n) = Machine.import
        #: (i32, ptr, word) -> word
        def self.write(i, p, n) = Machine.import
      end

      #: (word) -> void
      def zr_os_set_errno(n)
      end

      #: (ptr, ptr, word) -> ptr
      def zr_memcpy(to, from, n)
        Libc.memmove(to, from, n)
      end

      #: (ptr, word) -> void
      def say(text, n)
        Libc.write(Machine.i32(1), text, n)
      end

      #: (i32, ptr) -> i32
      def main(argc, argv)
        n = 1
        while n < 5000000
          c = zr_wasi_class_up(n)
          size = zr_wasi_class_size(c)
          if size < n || (n > 64 && size * 4 > n * 5 + 16) || zr_wasi_class_down(size) != c
            say(Machine.bytes("class\\n"), 6)
            return 1
          end
          n += n < 1000 ? 1 : 997
        end
        a = malloc(24)
        free(a)
        if malloc(20) != a || zr_os_malloc_size(a) != 32
          say(Machine.bytes("reuse\\n"), 6)
          return 1
        end
        Machine.store64(a, 0, 77)
        b = realloc(a, 1000)
        if Machine.load64(b, 0) != 77 || malloc(32) != a
          say(Machine.bytes("realloc\\n"), 8)
          return 1
        end
        slot = Machine.slot(8)
        before = Machine.word(Libc.zr_wasm_sbrk(0))
        posix_memalign(slot, 4096, 5000)
        q = Machine.ptr(Machine.load64(slot, 0))
        if (Machine.word(q) & 4095) != 0 || zr_os_malloc_size(q) < 5000
          say(Machine.bytes("align\\n"), 6)
          return 1
        end
        g = malloc(16)
        if Machine.word(q) - before >= 64 && (Machine.word(g) < before || Machine.word(g) >= Machine.word(q))
          say(Machine.bytes("gap\\n"), 4)
          return 1
        end
        free(q)
        posix_memalign(slot, 4096, 3000)
        if Machine.ptr(Machine.load64(slot, 0)) != q
          say(Machine.bytes("again\\n"), 6)
          return 1
        end
        if malloc(5000000000) != 0
          say(Machine.bytes("huge\\n"), 5)
          return 1
        end
        say(Machine.bytes("ok\\n"), 3)
        0
      end
    end
  RUBY

  def test_the_wasi_allocator_reuses_freed_blocks
    malloc = File.join(ROOT, "lib/zr/runtime/kernel/os/wasi/malloc.rb")
    functions, data = Zr::Machine::Lower.new([[File.read(malloc), malloc], [ALLOCATOR, "allocator.rb"]], Zr::Machine::Symbols.new).run
    Dir.mktmpdir("zr-wasm-") do |dir|
      wasm = File.join(dir, "allocator.wasm")
      assert_nil Zr::Native::Build.wasm(functions, data, wasm)
      run_module(wasm, "ok\n")
    end
  end

  # An import of a name that the module imports already, with another
  # signature, is refused, and the message gives both imports.
  def test_an_import_with_another_signature_is_refused
    source = IMPORTED.sub("#: (i32, i32, i32, i32) -> i32", "#: (i32, i32, i32) -> i32").sub("fd_write(i1, i2, i3, i4)", "fd_write(i1, i2, i3)")
                     .sub(", Machine.i32(iov + 8))", ")")
    functions, data = Zr::Machine.compile(source, "imported.rb")
    Dir.mktmpdir("zr-wasm-") do |dir|
      message = Zr::Native::Build.wasm(functions, data, File.join(dir, "imported.wasm"))
      assert_match(/\Afd_write is imported as .*params.* and .*params/, message)
    end
  end

  # Initialized data goes before bss, and adjacent objects share a
  # segment. A module that includes the compiler has about 90,000 data
  # objects, and wasmtime 48 could not compile more than 65,535 segments
  # (backend/wasm/codegen.rb, SEGMENT_GAP).
  def test_data_objects_share_a_segment
    functions, data = Zr::Machine.compile(IMPORTED, "imported.rb")
    data += 100.times.flat_map do |i|
      [Zr::Obj::Datum.new("zr_test_data_#{i}", :data, i.to_s, align: 8), Zr::Obj::Datum.new("zr_test_bss_#{i}", :bss, 64, align: 8)]
    end
    Dir.mktmpdir("zr-wasm-") do |dir|
      wasm = File.join(dir, "segments.wasm")
      assert_nil Zr::Native::Build.wasm(functions, data, wasm)
      assert_equal 1, data_segments(File.binread(wasm))
      run_module(wasm, "hi\n")
    end
  end

  NO_PENDING = { functions: [], data: [] }.freeze

  # A prelude's bodies are the same from workers and from this process,
  # and neither way changes the IR that it got. So the next prelude of
  # the process inlines and prepares the same IR
  # (`Native::Build.wasm_inlined`), not IR that the passes already ran on.
  def test_a_prelude_prepares_copies_in_workers_or_here
    functions, data = Zr::Native::Fixtures.build("indirect")
    functions = Zr::IR::Passes.inline(functions)
    before = functions.map { |f| Zr::IR::Fingerprint.of(f, Set.new) }

    preludes = %w[1 2].map do |jobs|
      with_env("ZR_JOBS" => jobs) do
        Zr::Backend::Wasm.prelude(functions, data, pending: NO_PENDING) { |all, codegen| Zr::Native::Build.prepared_bodies(all, codegen) }
      end
    end

    assert_equal before, functions.map { |f| Zr::IR::Fingerprint.of(f, Set.new) }
    refute_empty preludes.first.bodies
    assert_equal preludes.first.bodies, preludes.last.bodies
  end

  # The wasm body cache gives the bodies that the passes and the emitter
  # give, and a warm build runs no pass. A body that refers to the layout
  # keeps only the names, so the link puts in this layout's numbers.
  def test_a_prelude_from_the_body_cache_is_the_one_emitted
    functions, data = Zr::Native::Fixtures.build("indirect")
    functions = Zr::IR::Passes.inline(functions)
    Dir.mktmpdir("zr-wasm-cache-") do |dir|
      with_env("ZR_CACHE" => dir, "ZR_JOBS" => "1", "ZR_CODE_CACHE" => nil) do
        build = lambda do
          Zr::Backend::Wasm.prelude(functions, data, pending: NO_PENDING) do |all, codegen|
            Zr::Native::Build.prepared_bodies(all, codegen, Zr::Cache::Code.wasm("test"))
          end
        end
        cold = build.call
        warm = stub_method(Zr::IR::Passes, :prepare, ->(*) { flunk "a warm build ran the passes" }) { build.call }

        assert_equal Zr::Backend::Wasm.prelude(functions, data, pending: NO_PENDING) { |all, codegen|
          all.map { |f| codegen.body(Zr::IR::Passes.prepare(Marshal.load(Marshal.dump(f)))) }
        }.bodies, cold.bodies
        assert_equal cold.bodies, warm.bodies
      end
    end
  end

  # The janitor keeps what a wasm program reads, and a bundle (`zr cache
  # export`) holds it: its prelude, the runtime's symbol table and gem
  # prelude list, and the body packs that the next prelude takes its
  # bodies from.
  def test_a_wasm_prelude_roots_itself_the_runtimes_tables_and_the_body_packs
    Dir.mktmpdir("zr-wasm-root-") do |dir|
      with_env("ZR_CACHE" => dir) do
        prelude_list = Zr::Cache::Store.path(:meta, "1" * 64)
        runtime = Data.define(:target, :digest, :gem_prelude_path).new(Zr::Target::WASM32_WASI, "2" * 64, prelude_list)
        path = Zr::Cache::Store.path(:wasm, "0" * 64)

        Zr::Native::Build.wasm_root(runtime, path, nil)

        rooted = Zr::Cache::Store.rooted_paths(prefix: "wasm32-wasi-prelude-plain")
        assert_includes rooted, path
        assert_includes rooted, Zr::RuntimeSources.symbols_path(runtime.digest)
        assert_includes rooted, prelude_list
        assert_includes rooted, Zr::Cache::Code.dir(:wasm32)
      end
    end
  end

  # A body only reads the type section that the layout made, so another
  # process can emit it. A type that the layout did not add raises at
  # once: in a worker, it would be lost.
  def test_a_body_refuses_a_type_that_the_layout_did_not_add
    functions, data = Zr::Native::Fixtures.build("indirect")
    codegen = Zr::Backend::Wasm::Codegen.new(functions, data, pending: NO_PENDING)
    codegen.prelude { |all, emitter| all.map { |f| emitter.body(Zr::IR::Passes.prepare(f)) } }

    error = assert_raises(RuntimeError) { codegen.known_type_index([[0x7C] * 9, []]) }
    assert_match "is not in the type section", error.message
  end

  # The number of segments in the data section of a module.
  def data_segments(bytes)
    at = 8
    leb = lambda do
      value = shift = 0
      loop do
        byte = bytes.getbyte(at)
        at += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        return value if byte < 0x80
      end
    end
    while at < bytes.bytesize
      id = bytes.getbyte(at)
      at += 1
      size = leb.call
      return leb.call if id == 11

      at += size
    end
    0
  end

  # A program on the WASI layer reads what the host gives it: its
  # arguments, its environment, and the files of a preopened directory.
  # The expected output is what ruby 4.0 for wasm32-wasi printed for the
  # same program under the same wasmtime flags.
  HOST = <<~'RUBY'
    p ARGV, ENV["X"], ENV.key?("NOPE")
    ENV["Y"] = "set"
    p ENV["Y"]
    File.write("out.txt", "written\n")
    p File.read("out.txt"), File.size("out.txt"), File.directory?("."), Dir.children(".").sort
    begin
      File.read("missing")
    rescue => e
      p e
    end
    File.delete("out.txt")
    p File.exist?("out.txt"), $$, RUBY_PLATFORM, Process.clock_gettime(Process::CLOCK_MONOTONIC) > 0
  RUBY

  def test_a_program_reads_its_host
    skip Checks.wasm_missing if Checks.wasm_missing

    Dir.mktmpdir("zr-wasm-") do |dir|
      File.write(File.join(dir, "host.rb"), HOST)
      program = Zr::Program.build(HOST, File.join(dir, "host.rb"), Zr::BuildOptions.new(target: Zr::Target::WASM32_WASI))
      wasm = File.join(dir, "host.wasm")
      assert_nil Zr::Native::Build.wasm_program(program, wasm)
      argv = Zr::Harness::Wasmtime.run(wasm, "a", "b", dirs: { "." => "." }, env: { "X" => "1" })
      answer = Checks.run(argv, chdir: dir, merge: true)
      refute Checks.killed(answer), "wasmtime was killed at #{Checks.killed(answer)}: #{answer.stdout}"
      assert_equal <<~'OUT', answer.stdout
        ["a", "b"]
        "1"
        false
        "set"
        "written\n"
        8
        true
        ["host.rb", "host.wasm", "out.txt"]
        #<Errno::ENOENT: No such file or directory @ rb_sysopen - missing>
        false
        42
        "wasm32-wasi"
        true
      OUT
    end
  end

  # A program module imports the runtime from a runtime module of its own
  # (`wasm_program` with `split`), which wasmtime compiles once and
  # preloads. It must run as the whole module runs: an address that the
  # program takes of a runtime function, a block that the runtime calls
  # back into, and the program's data, which its `_start` copies in.
  def test_a_program_module_runs_as_the_whole_module_does
    skip Checks.wasm_missing if Checks.wasm_missing

    source = "def m(*a, &b) = b.call(a)\nh = { a: [3, 1, 2].sort }\np h, m(1, 2) { |x| x.size }, [1, 2].map(&:succ)\n"
    Dir.mktmpdir("zr-wasm-") do |dir|
      program = Zr::Program.build(source, File.join(dir, "split.rb"), Zr::BuildOptions.new(target: Zr::Target::WASM32_WASI))
      whole = File.join(dir, "whole.wasm")
      split = File.join(dir, "split.wasm")
      assert_nil Zr::Native::Build.wasm_program(program, whole)
      assert_nil Zr::Native::Build.wasm_program(program, split, split: dir)
      runtime = Zr::Harness::Wasmtime.runtime_of(split)

      assert_nil Zr::Harness::Wasmtime.runtime_of(whole)
      assert_path_exists File.join(dir, runtime)
      assert_operator File.size(split), :<, File.size(whole) / 10
      compiled = Zr::Harness::Wasmtime.runtime(File.join(dir, runtime))
      outputs = [Zr::Harness::Wasmtime.run(whole), Zr::Harness::Wasmtime.run(split, preload: compiled)].map do |argv|
        Checks.run(argv, chdir: dir, merge: true).stdout
      end
      assert_equal ["{a: [1, 2, 3]}\n2\n[2, 3]\n"] * 2, outputs
    end
  end

  Dir[File.join(ROOT, "test/machine/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_zr_#{name}") do
      functions, data, raw = Zr::Machine.compile(File.read(rb), rb)
      skip "#{name} names a raw function" unless raw.empty?

      Dir.mktmpdir("zr-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Zr::Native::Build.wasm(functions, data, wasm)
        run_module(wasm, File.binread(rb.sub(/\.rb\z/, ".out")))
        run_module(wasm, File.binread(rb.sub(/\.rb\z/, ".out")), "stress") if name == "gc"
      end
    end
  end

  # The kernel core, as `runtime_test.rb` links it natively.
  Zr::Test::RuntimePrograms::FILES.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_rt_#{name}") do
      skip Checks.wasm_missing if Checks.wasm_missing

      want, status = Zr::Test::RuntimePrograms.expected(rb)
      program = Zr::Test::RuntimePrograms.compile(rb, Zr::Target::WASM32_WASI)
      Dir.mktmpdir("zr-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Zr::Native::Build.wasm_program(program, wasm)
        run_module(wasm, want, status: status)
      end
    end
  end

  Dir[File.join(ROOT, "test/machine/units/*/")].sort.each do |unit|
    name = File.basename(unit)
    define_method("test_zr_unit_#{name}") do
      compiled = Zr::Machine.unit(Dir[File.join(unit, "*.rb")].sort)
      functions, data, raw = compiled.functions, compiled.data, compiled.raw
      Dir.mktmpdir("zr-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Zr::Native::Build.wasm(functions, data, wasm, raw: raw)
        run_module(wasm, File.binread(File.join(unit, "out")))
      end
    end
  end
end
