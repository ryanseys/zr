# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/machine/lower"
require_relative "../../lib/ze0/native/build"
require_relative "../../test/native/fixtures"
require "support/rt_programs"

# The wasm road: every hand-written IR program, every kernel-dialect
# program that names no raw function, and every kernel core becomes one
# WASI module, and wasmtime prints what the binary prints.
#
# Every wasm row is here, so a failure names the wasm backend and
# nothing else. The same programs go through the aarch64 backend in
# `native_test.rb`, `zr_test.rb` and `rt_test.rb`.
class WasmTest < Minitest::Test
  def run_module(wasm, expected, *args, status: 0)
    skip "wasmtime is not installed" unless Checks.wasmtime?

    out, why = Checks.bounded({}, [WASMTIME, *WASM_FLAGS, wasm, *args], err: %i[child out])
    refute why, "wasmtime was killed at #{why}: #{out}"
    assert_equal status, $?.exitstatus, "wasmtime exited #{$?.exitstatus}: #{out}"
    assert_equal expected, out
  end

  Ze0::Native::Fixtures::NAMES.each do |name|
    define_method("test_native_#{name}") do
      functions, data = Ze0::Native::Fixtures.build(name)
      Dir.mktmpdir("ze0-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm(functions, data, wasm)
        run_module(wasm, File.binread(File.join(ROOT, "test/native/#{name}.stdout")))
      end
    end
  end

  # A dialect import that names its wasm module reaches the host's own
  # call, and a native build refuses it by name.
  IMPORTED = <<~RUBY
    Machine.import "fd_write", [I32, I32, I32, I32] => I32, from: "wasi_snapshot_preview1"

    sig [I32, Ptr] => I32
    machine def main(argc, argv)
      iov = Machine.slot(16)
      Machine.store32(iov, 0, Machine.i32(Machine.bytes("hi\n")))
      Machine.store32(iov, 4, Machine.i32(3))
      fd_write(Machine.i32(1), Machine.i32(iov), Machine.i32(1), Machine.i32(iov + 8))
      0
    end
  RUBY

  def test_an_import_from_a_wasm_module
    functions, data = Ze0::Machine.compile(IMPORTED, "imported.rb")
    Dir.mktmpdir("ze0-wasm-") do |dir|
      wasm = File.join(dir, "imported.wasm")
      assert_nil Ze0::Native::Build.wasm(functions, data, wasm)
      run_module(wasm, "hi\n")
      assert_equal "fd_write is a wasm import from wasi_snapshot_preview1, which no native link has",
                   Ze0::Native::Build.binary(functions, data, File.join(dir, "imported"), work: dir)
    end
  end

  # Initialized data goes before bss, and objects side by side share a
  # segment. A module that carries the compiler has some 90,000 data
  # objects, and wasmtime 48 cannot compile past 65,535 segments.
  def test_data_objects_share_a_segment
    functions, data = Ze0::Machine.compile(IMPORTED, "imported.rb")
    data += 100.times.flat_map do |i|
      [Ze0::Obj::Data.new("zr_test_data_#{i}", :data, i.to_s, align: 8), Ze0::Obj::Data.new("zr_test_bss_#{i}", :bss, 64, align: 8)]
    end
    Dir.mktmpdir("ze0-wasm-") do |dir|
      wasm = File.join(dir, "segments.wasm")
      assert_nil Ze0::Native::Build.wasm(functions, data, wasm)
      assert_equal 1, data_segments(File.binread(wasm))
      run_module(wasm, "hi\n")
    end
  end

  # How many segments a module's data section holds.
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
      size = leb.()
      return leb.() if id == 11

      at += size
    end
    0
  end

  # A program on the WASI layer reads what the host hands it: its
  # arguments, its environment, and the files of a preopened directory.
  # The answer is what ruby 4.0 for wasm32-wasi printed for the same
  # program under the same wasmtime flags.
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
    skip "wasmtime is not installed" unless Checks.wasmtime?

    Dir.mktmpdir("ze0-wasm-") do |dir|
      File.write(File.join(dir, "host.rb"), HOST)
      program = Ze0::Zr.program(HOST, File.join(dir, "host.rb"), target: Ze0::Target::WASM32_WASI)
      wasm = File.join(dir, "host.wasm")
      assert_nil Ze0::Native::Build.wasm_program(program, wasm)
      out, why = Checks.bounded({}, [WASMTIME, "run", *WASM_FLAGS, "--dir", ".", "--env", "X=1", wasm, "a", "b"], err: %i[child out], chdir: dir)
      refute why, "wasmtime was killed at #{why}: #{out}"
      assert_equal <<~'OUT', out
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

  Dir[File.join(ROOT, "test/zr/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_zr_#{name}") do
      functions, data, raw = Ze0::Machine.compile(File.read(rb), rb)
      skip "#{name} names a raw function" unless raw.empty?

      Dir.mktmpdir("ze0-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm(functions, data, wasm)
        run_module(wasm, File.binread(rb.sub(/\.rb\z/, ".stdout")))
        run_module(wasm, File.binread(rb.sub(/\.rb\z/, ".stdout")), "stress") if name == "gc"
      end
    end
  end

  # The kernel core, as `rt_test.rb` links it natively.
  RtPrograms::FILES.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_rt_#{name}") do
      want, status = RtPrograms.expected(rb)
      program = RtPrograms.compile(rb, Ze0::Target::WASM32_WASI)
      Dir.mktmpdir("ze0-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm_program(program, wasm)
        run_module(wasm, want, status: status)
      end
    end
  end

  Dir[File.join(ROOT, "test/zr/units/*/")].sort.each do |unit|
    name = File.basename(unit)
    define_method("test_zr_unit_#{name}") do
      functions, data, raw = Ze0::Machine.compile_unit(Dir[File.join(unit, "*.rb")].sort)
      Dir.mktmpdir("ze0-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm(functions, data, wasm, raw: raw)
        run_module(wasm, File.binread(File.join(unit, "stdout")))
      end
    end
  end
end
