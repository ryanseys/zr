# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/machine/lower"
require_relative "../../lib/ze0/native/build"
require_relative "../../test/native/fixtures"

# The wasm road: every hand-written IR program and every kernel-dialect
# program that names no raw function becomes one WASI module, and wasmtime
# prints what the binary prints.
class WasmTest < Minitest::Test
  WASMTIME = ENV["WASMTIME"] || "wasmtime"

  def self.wasmtime?
    system(WASMTIME, "--version", out: File::NULL, err: File::NULL)
  end

  def run_module(wasm, expected, *args)
    skip "wasmtime is not installed" unless self.class.wasmtime?

    out = IO.popen([WASMTIME, wasm, *args], &:read)
    assert_equal 0, $?.exitstatus, "wasmtime exited #{$?.exitstatus}"
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
