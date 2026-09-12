# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"

# The kernel core: each `test/rt/<name>.rb` is a hand-written toplevel
# in the dialect, linked with `rt/kernel/` into a binary and into a
# module under wasmtime, and prints `<name>.stdout` (stderr
# folded in) and exits with `<name>.exit` (0 when absent), plain and
# with a collection at every allocation.
class RtTest < Minitest::Test
  WASMTIME = ENV["WASMTIME"] || "wasmtime"

  def compile(rb)
    symbols = Ze0::Machine::Symbols.new
    unit = Ze0::Machine.unit(Ze0::Zr::KERNEL + [rb], symbols: symbols)
    functions, data = Ze0::Zr.core(unit, symbols)
    [unit.functions + functions, unit.data + data + Ze0::Zr.symbol_names(symbols), unit.raw]
  end

  Dir[File.join(ROOT, "test/rt/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    want = File.binread(rb.sub(/\.rb\z/, ".stdout"))
    status = File.file?(rb.sub(/\.rb\z/, ".exit")) ? Integer(File.read(rb.sub(/\.rb\z/, ".exit"))) : 0
    define_method("test_#{name}") do
      functions, data, raw = compile(rb)
      Dir.mktmpdir("ze0-rt-") do |dir|
        bin = File.join(dir, name)
        assert_nil Ze0::Native::Build.binary(functions, data, bin, work: dir, raw: raw)
        [{}, { "ZR_GC_STRESS" => "1" }].each do |env|
          out = IO.popen(env, [bin], err: %i[child out], &:read)
          assert_equal status, $?.exitstatus, "#{name} (#{env}) exited #{$?.exitstatus}: #{out}"
          assert_equal want, out
        end
      end
    end

    define_method("test_wasm_#{name}") do
      skip "wasmtime is not installed" unless system(WASMTIME, "--version", out: File::NULL, err: File::NULL)

      functions, data, raw = compile(rb)
      Dir.mktmpdir("ze0-rt-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm(functions, data, wasm, raw: raw)
        out = IO.popen([WASMTIME, wasm], err: %i[child out], &:read)
        assert_equal status, $?.exitstatus, "wasmtime exited #{$?.exitstatus}: #{out}"
        assert_equal want, out
      end
    end
  end
end
