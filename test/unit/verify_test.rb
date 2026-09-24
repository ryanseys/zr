# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/ir/verify"

# The strict verifier checks the type of every operand, not only the
# arguments of a jump. It refuses an `i8` compared with an `i64` (#43)
# where the instruction is made, on every target. It also refuses a
# call with the wrong arguments.
class VerifyTest < Minitest::Test
  Verify = Zr::IR::Verify

  def function(params, ret)
    f = Zr::IR::Function.new("probe", params, ret)
    yield f, *f.args
    f
  end

  def refused(f)
    e = assert_raises(Verify::Error) { Verify.check(f, strict: true) }
    e.message
  end

  def test_a_well_typed_function_passes
    f = function(%w[i64 i64], "i64") do |f, a, b|
      flag = f.icmp("slt", a, b)
      f.ret(f.csel(flag, a, b))
    end

    assert_same f, Verify.check(f, strict: true)
  end

  def test_a_comparison_of_two_widths_is_refused
    f = function(%w[i64], "i8") do |f, a|
      narrow = f.ireduce("i8", a)
      f.ret(f.icmp("eq", narrow, a))
    end

    assert_match(/icmp takes v\d+ \(i64\) where i8 is wanted/, refused(f))
  end

  def test_a_binary_operation_takes_its_result_type_on_both_sides
    f = function(%w[i64 i32], "i64") do |f, a, b|
      f.ret(f.iadd(a, b))
    end

    assert_match(/iadd takes v\d+ \(i32\) where i64 is wanted/, refused(f))
  end

  def test_a_shift_takes_any_integer_amount
    f = function(%w[i64 i32], "i64") do |f, a, b|
      f.ret(f.binop(:ishl, a, b))
    end

    assert_same f, Verify.check(f, strict: true)
  end

  def test_an_immediate_operand_is_not_typed
    f = function(%w[i64], "i64") { |f, a| f.ret(f.iadd(a, 1)) }

    assert_same f, Verify.check(f, strict: true)
  end

  def test_a_jump_passes_each_parameters_type_or_an_immediate
    f = function(%w[i64], "i64") do |f, a|
      done, (v,) = f.block(%w[i64])
      f.jump(done, [1])
      f.switch(done)
      f.ret(f.iadd(v, a))
    end

    assert_same f, Verify.check(f, strict: true)

    g = function(%w[i64], "i64") do |f, a|
      done, (v,) = f.block(%w[i32])
      f.jump(done, [a])
      f.switch(done)
      f.ret(f.uextend("i64", v))
    end

    assert_match(/passes v\d+ \(i64\) to \w+, whose parameter is i32/, refused(g))
  end

  def test_a_call_passes_what_its_signature_takes
    f = function(%w[i64 i32], "i64") do |f, a, b|
      callee = f.callee("twice", %w[i64], "i64", colocated: false)
      f.ret(f.call_val(callee, [a, b]))
    end

    assert_match(/passes 2 argument\(s\) to fn0, which takes 1/, refused(f))

    g = function(%w[i64 i32], "i64") do |f, _, b|
      callee = f.callee("twice", %w[i64], "i64", colocated: false)
      f.ret(f.call_val(callee, [b]))
    end

    assert_match(/call takes v\d+ \(i32\) where i64 is wanted/, refused(g))
  end

  def test_an_extend_widens_and_a_reduce_narrows
    f = function(%w[i64], "i64") { |f, a| f.ret(f.uextend("i64", a)) }

    assert_match(/uextend takes v\d+ \(i64\) to i64, which is not narrower/, refused(f))
  end

  def test_a_return_has_the_functions_type
    f = function(%w[i64], "i32") { |f, a| f.ret(a) }

    assert_match(/return takes v\d+ \(i64\) where i32 is wanted/, refused(f))
  end
end
