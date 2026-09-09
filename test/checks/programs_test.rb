# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"
require_relative "../../lib/ze0/harness/case"

# Ruby programs on the zr runtime: each `test/programs/<name>.rb` runs under
# ruby, the oracle, and then compiled with the kernel on both native
# roads and under wasmtime; stdout, stderr and the exit status must
# agree. The Cranelift road also runs with a collection at every
# allocation: the roots are the lowering's, the same on both roads, and
# the Ruby road's code is slow under that many collections. The oracle
# runs without error_highlight or did_you_mean, as the corpus was recorded.
# A program whose first line says "native only" reads the host (its
# environment or working directory) and skips the wasm road; one whose
# first line says "no stress" allocates too much for a collection at
# every allocation and skips that column.
class ProgramsTest < Minitest::Test
  ROADS = { ruby: Ze0::Native::Build.road("ruby", ROOT), cranelift: Ze0::Native::Build.road("cranelift", ROOT) }.freeze
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

  def check(label, name, env, argv, want, rb)
    out, err, status = capture(env, argv)
    assert_equal want[2], status, "#{name} on the #{label} road (#{env}) exited #{status}: #{out}#{err}"
    assert_equal scrub(want[0], rb), scrub(out, rb)
    assert_equal scrub(want[1], rb), scrub(err, rb)
  end

  Dir[File.join(ROOT, "test/programs/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    ROADS.each do |label, road|
      define_method("test_#{label}_#{name}") do
        skip "clif2obj is not built (bin/ze0 native build)" unless road.available?

        want = oracle(rb)
        program = Ze0::Zr.program(File.read(rb), rb)
        Dir.mktmpdir("ze0-programs-") do |dir|
          bin = File.join(dir, name)
          assert_nil Ze0::Native::Build.program(program, bin, road: road, work: dir)
          check(label, name, {}, [bin], want, rb)
          stress = label == :cranelift && !File.open(rb, &:readline).include?("no stress")
          check(label, name, { "ZR_GC_STRESS" => "1" }, [bin], want, rb) if stress
        end
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
        check(:wasm, name, {}, [WASMTIME, wasm], want, rb)
      end
    end
  end
end
