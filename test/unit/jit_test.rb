# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/native/build"
require_relative "../../lib/ze0/obj/jit/fiddle"
require_relative "../../test/native/fixtures"

# The in-process road: a unit the Ruby backend wrote, loaded into this
# ruby and called through Fiddle. `exit` is swapped for a call that
# returns, so the program's own exit does not end the test.
class JITTest < Minitest::Test
  # Mach-O, libSystem and the darwin JIT: only a darwin host has them.
  def setup
    skip "needs an aarch64-apple-darwin host" unless Ze0::Target::AARCH64_DARWIN.native?
  end

  def call_main(name)
    functions, data = Ze0::Native::Fixtures.build(name)
    unit = Ze0::Native::Build.unit(functions, data)
    unit.functions.each { |f| f.relocs.each { |r| r.symbol = "getpid" if r.symbol == "exit" } }
    symbols = Ze0::Obj::JIT.load(unit, host: Ze0::Obj::JIT::Fiddle.new)
    main = Fiddle::Function.new(symbols["main"], [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    out, = capture_subprocess_io { $stdout.flush; main.call(0, 0) }
    out
  end

  def test_loops_print_in_process
    assert_equal "5050\n", call_main("loops")
  end

  def test_hello_prints_in_process
    assert_equal "hello, ze0!\n", call_main("hello")
  end

  def test_arith_holds_in_process
    assert_equal "", call_main("arith")
  end
end
