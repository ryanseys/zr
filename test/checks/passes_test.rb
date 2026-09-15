# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/ir/passes"
require_relative "../../lib/ze0/ir/interp"

# The IR passes, one shape each: what a pass makes of a function, and
# that the interpreter answers the same before and after it.
class PassesTest < Minitest::Test
  def function(name, params, ret)
    f = Ze0::IR::Function.new(name, params, ret)
    yield f, *f.args
    f
  end

  def ops(f) = f.blocks.flat_map { |b| b.insts.map(&:op) }

  def answer(f, args)
    Ze0::IR::Interp.new([f]).answer(f.name, args)
  end

  def test_constants_fold_through_the_integer_operations
    f = function("fold", [], "i64") do |f|
      a = f.iadd(f.iconst("i64", 40), f.iconst("i64", 2))
      b = f.sdiv(f.iconst("i64", -7), f.iconst("i64", 2))
      c = f.ishl(f.iconst("i32", 1), f.iconst("i32", 33))
      f.ret(f.iadd(a, f.iadd(b, f.uextend("i64", c))))
    end
    was = answer(f, [])
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal %i[iconst return], ops(f)
    assert_equal was, answer(f, [])
    assert_equal (42 - 3 + 2) & 0xFFFF_FFFF_FFFF_FFFF, was
  end

  def test_an_identity_is_its_operand_and_a_branch_on_a_constant_is_a_jump
    f = function("identity", %w[i64], "i64") do |f, x|
      y = f.iadd(x, f.iconst("i64", 0))
      z = f.imul(f.iconst("i64", 1), y)
      yes = f.label
      no = f.label
      f.brif(f.icmp("eq", f.iconst("i64", 3), f.iconst("i64", 3)), yes, no)
      f.switch(yes)
      f.ret(z)
      f.switch(no)
      f.ret(f.iconst("i64", 0))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal %i[iconst jump return return], ops(f)
    assert_equal ["v0"], f.entry_block.insts.last.targets.map { |(name, _)| f.blocks.find { |b| b.name == name }.insts.first.args.first }
    assert_equal 9, answer(f, [9])
  end

  def test_dead_code_goes_and_a_store_stays
    f = function("dead", %w[i64], nil) do |f, p|
      f.iconst("i64", 5)
      f.iadd(f.iconst("i64", 1), p)
      f.store(f.iconst("i64", 8), p)
      f.ret
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal %i[iconst store return], ops(f)
  end

  def test_a_select_between_one_value_is_that_value
    f = function("same", %w[i8 i64], "i64") do |f, c, x|
      f.ret(f.csel(c, x, x))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal %i[return], ops(f)
    assert_equal ["v1"], f.entry_block.insts.first.args
  end
end
