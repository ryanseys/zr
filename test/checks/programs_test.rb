# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"
require_relative "../../lib/ze0/harness/case"

# Ruby programs on the zr runtime: each `test/programs/<name>.rb` runs
# under ruby, the oracle, and then compiled with the kernel and under
# wasmtime; stdout, stderr and the exit status must agree. The oracle
# runs without error_highlight or did_you_mean, as the corpus was recorded.
# A program whose first line says "native only" reads the host (its
# environment or working directory) and skips the wasm road; one whose
# first line says "no stress" allocates too much for a collection at
# every allocation and skips that column.
#
# `ZE0_STRESS=1` adds the collect-at-every-allocation column. It is off by
# default because spill-everything code is slow under that many
# collections; `IR::Arm64`'s second allocator (plan B4) is what makes it
# cheap enough to run always.
class ProgramsTest < Minitest::Test
  WASMTIME = ENV["WASMTIME"] || "wasmtime"

  # `[stdout, stderr, status]` of `argv` under `env`.
  def capture(env, argv)
    Dir.mktmpdir("ze0-programs-err-") do |dir|
      err = File.join(dir, "err")
      out = IO.popen(env, argv, err: err, &:read)
      [out, File.read(err), $?.exitstatus]
    end
  end

  def oracle(rb)
    capture({}, [RbConfig.ruby, "--disable-error_highlight", "--disable-did_you_mean", rb])
  end

  def scrub(text, rb)
    Ze0::Harness::Normalize.bytes(text, rb, File.dirname(rb))
  end

  def check(name, env, argv, want, rb)
    out, err, status = capture(env, argv)
    assert_equal want[2], status, "#{name} (#{env}) exited #{status}: #{out}#{err}"
    assert_equal scrub(want[0], rb), scrub(out, rb)
    assert_equal scrub(want[1], rb), scrub(err, rb)
  end

  Dir[File.join(ROOT, "test/programs/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      want = oracle(rb)
      program = Ze0::Zr.program(File.read(rb), rb)
      Dir.mktmpdir("ze0-programs-") do |dir|
        bin = File.join(dir, name)
        assert_nil Ze0::Native::Build.program(program, bin, work: dir)
        check(name, {}, [bin], want, rb)
        stress = ENV["ZE0_STRESS"] == "1" && !File.open(rb, &:readline).include?("no stress")
        check(name, { "ZR_GC_STRESS" => "1" }, [bin], want, rb) if stress
      end
    end

    define_method("test_wasm_#{name}") do
      skip "wasmtime is not installed" unless system(WASMTIME, "--version", out: File::NULL, err: File::NULL)
      skip "the program reads the host" if File.open(rb, &:readline).include?("native only")

      want = oracle(rb)
      program = Ze0::Zr.program(File.read(rb), rb)
      Dir.mktmpdir("ze0-programs-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm_program(program, wasm)
        check(name, {}, [WASMTIME, wasm], want, rb)
      end
    end
  end
end
