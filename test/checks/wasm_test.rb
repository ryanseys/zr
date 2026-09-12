# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/machine/lower"
require_relative "../../lib/ze0/native/build"
require_relative "../../test/native/fixtures"
require_relative "rt_test"

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
  Dir[File.join(ROOT, "test/rt/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    exit_file = rb.sub(/\.rb\z/, ".exit")
    status = File.file?(exit_file) ? Integer(File.read(exit_file)) : 0
    define_method("test_rt_#{name}") do
      functions, data, raw = RtTest.compile(rb)
      Dir.mktmpdir("ze0-wasm-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm(functions, data, wasm, raw: raw)
        run_module(wasm, File.binread(rb.sub(/\.rb\z/, ".stdout")), status: status)
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
