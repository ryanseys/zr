# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/obj/jit/fiddle"
require_relative "../../test/native/fixtures"

# Runs code in this process: the test loads a unit from the Ruby backend
# into this ruby and calls it through Fiddle. A call that returns
# replaces `exit`, so that the program's exit does not stop the test.
class JITTest < Minitest::Test
  # Only a darwin host has Mach-O, libSystem and the darwin JIT.
  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  def call_main(name)
    functions, data = Zr::Native::Fixtures.build(name)
    unit = Zr::Native::Build.unit(functions, data)
    unit.functions.each { |f| f.relocs.each { |r| r.symbol = "getpid" if r.symbol == "exit" } }
    symbols = Zr::Obj::JIT.load(unit, host: Zr::Obj::JIT::Fiddle.new)
    main = Fiddle::Function.new(symbols["main"], [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    out, = capture_subprocess_io do
      $stdout.flush
      main.call(0, 0)
    end
    out
  end

  def test_loops_print_in_process
    assert_equal "5050\n", call_main("loops")
  end

  def test_hello_prints_in_process
    assert_equal "hello, zr!\n", call_main("hello")
  end

  def test_arith_passes_in_process
    assert_equal "", call_main("arith")
  end
end
