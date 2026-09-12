# frozen_string_literal: true

require_relative "helper"
require "json"
require_relative "../../lib/ze0/native/ruby"
require_relative "../../lib/ze0/obj/jit/fiddle"

# The in-process road: a unit the Ruby backend wrote, loaded into this
# ruby and called through Fiddle. `exit` is swapped for a call that
# returns, so the program's own exit does not end the test.
class JITTest < Minitest::Test

  def call_main(name)
    clif = File.join(ROOT, "test/native/#{name}.clif")
    data = File.join(ROOT, "test/native/#{name}.json")
    unit = Ze0::Native::Ruby.unit_for(File.read(clif), File.file?(data) ? JSON.parse(File.read(data)) : {})
    unit.functions.each { |f| f.relocs.each { |r| r.symbol = "getpid" if r.symbol == "exit" } }
    symbols = Ze0::Obj::JIT.load(unit, host: Ze0::Obj::JIT::Fiddle.new)
    main = Fiddle::Function.new(symbols["main"], [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    out, = capture_subprocess_io { $stdout.flush; main.call(0, 0) }
    out
  end

  def test_loop_prints_in_process
    assert_equal "5050\n", call_main("loop")
  end

  def test_hello_prints_in_process
    assert_equal "hello, ze0!\n", call_main("hello")
  end

  def test_arith_holds_in_process
    assert_equal "", call_main("arith")
  end
end
