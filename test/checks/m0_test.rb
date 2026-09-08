# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"

# Ruby programs on the zr runtime: each `test/m0/<name>.rb` runs under
# ruby, the oracle, and then compiled with the kernel on both native
# roads (plain and with a collection at every allocation) and under
# wasmtime; stdout, stderr and the exit status must agree.
class M0Test < Minitest::Test
  ROADS = { ruby: Ze0::Native::Build.road("ruby", ROOT), cranelift: Ze0::Native::Build.road("cranelift", ROOT) }.freeze
  WASMTIME = ENV["WASMTIME"] || "wasmtime"

  # `[stdout, stderr, status]` of `argv` under `env`.
  def capture(env, argv)
    Dir.mktmpdir("ze0-m0-err-") do |dir|
      err = File.join(dir, "err")
      out = IO.popen(env, argv, err: err, &:read)
      [out, File.read(err), $?.exitstatus]
    end
  end

  def oracle(rb)
    capture({}, [RbConfig.ruby, rb])
  end

  # CRuby's error line starts with `file:line:in '<main>': `, and a
  # snippet with carets follows; the runtime prints the message alone
  # until exceptions and backtraces exist.
  def scrub(err)
    err.lines.first.to_s.sub(/\A\S+:\d+:in '[^']*': /, "")
  end

  def check(label, name, env, argv, want)
    out, err, status = capture(env, argv)
    assert_equal want[2], status, "#{name} on the #{label} road (#{env}) exited #{status}: #{out}#{err}"
    assert_equal want[0], out
    assert_equal scrub(want[1]), err
  end

  Dir[File.join(ROOT, "test/m0/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    ROADS.each do |label, road|
      define_method("test_#{label}_#{name}") do
        skip "clif2obj is not built (bin/ze0 native build)" unless road.available?

        want = oracle(rb)
        functions, data, raw = Ze0::Zr.program(File.read(rb), rb)
        Dir.mktmpdir("ze0-m0-") do |dir|
          bin = File.join(dir, name)
          assert_nil Ze0::Native::Build.binary(functions, data, bin, road: road, work: dir, raw: raw)
          [{}, { "ZR_GC_STRESS" => "1" }].each { |env| check(label, name, env, [bin], want) }
        end
      end
    end

    define_method("test_wasm_#{name}") do
      skip "wasmtime is not installed" unless system(WASMTIME, "--version", out: File::NULL, err: File::NULL)

      want = oracle(rb)
      functions, data, raw = Ze0::Zr.program(File.read(rb), rb)
      Dir.mktmpdir("ze0-m0-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm(functions, data, wasm, raw: raw)
        check(:wasm, name, {}, [WASMTIME, wasm], want)
      end
    end
  end
end
