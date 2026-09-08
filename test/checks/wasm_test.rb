# frozen_string_literal: true

require_relative "helper"
require "json"
require_relative "../../lib/ze0/machine/lower"
require_relative "../../lib/ze0/native/build"

# The wasm road: every hand-written CLIF program and every kernel-dialect
# program that names no raw function becomes one WASI module, and wasmtime
# prints what the native roads print.
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

  Dir[File.join(ROOT, "test/native/*.clif")].sort.each do |clif|
    name = File.basename(clif, ".clif")
    define_method("test_native_#{name}") do
      functions = Ze0::IR::ClifText.parse(File.read(clif))
      side = clif.sub(/\.clif\z/, ".json")
      rows = File.file?(side) ? JSON.parse(File.read(side)).fetch("data", []) : []
      data = rows.map { |d| Ze0::Obj::Data.new(d["name"], d["section"].to_sym, [d["bytes"]].pack("H*"), align: d.fetch("align", 1)) }
      Dir.mktmpdir("ze0-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm(functions, data, wasm)
        run_module(wasm, File.binread(clif.sub(/\.clif\z/, ".stdout")))
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
