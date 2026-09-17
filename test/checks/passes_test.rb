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
    assert_equal %i[return], ops(f)
    assert_equal ["v0"], f.entry_block.insts.first.args
    assert_equal 9, answer(f, [9])
  end

  def test_a_parameter_every_edge_gives_one_constant_folds_where_it_is_read
    f = function("joined", %w[i64], "i64") do |f, p|
      yes = f.label
      no = f.label
      join, (size,) = f.block(["i64"])
      f.brif(f.icmp("eq", p, f.iconst("i64", 0)), yes, no)
      f.switch(yes)
      f.jump(join, [f.iconst("i64", 24)])
      f.switch(no)
      f.jump(join, [f.iconst("i64", 24)])
      f.switch(join)
      small = f.label
      large = f.label
      f.brif(f.icmp("sle", size, f.iconst("i64", 32)), small, large)
      f.switch(small)
      f.ret(f.iadd(p, f.iconst("i64", 1)))
      f.switch(large)
      f.ret(f.iconst("i64", 0))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 1, ops(f).count(:icmp), "only the entry's own test is left"
    assert_equal [1, 8], [answer(f, [0]), answer(f, [7])]
  end

  def test_a_loop_head_is_not_taken_for_a_constant
    f = function("loop", %w[i64], "i64") do |f, n|
      head, (i,) = f.block(["i64"])
      body = f.label
      done = f.label
      f.jump(head, [f.iconst("i64", 0)])
      f.switch(head)
      f.brif(f.icmp("slt", i, n), body, done)
      f.switch(body)
      f.jump(head, [f.iadd(i, f.iconst("i64", 1))])
      f.switch(done)
      f.ret(i)
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal [5, 0], [answer(f, [5]), answer(f, [-3])]
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

  def test_a_load_reads_what_the_last_store_to_its_slot_put
    f = function("forward", %w[i64 i64], "i64") do |f, x, y|
      rec = f.stack_addr(f.slot(32))
      f.store(x, rec, 8)
      f.store(y, rec, 16)
      a = f.fetch("i64", f.iadd(rec, f.iconst("i64", 8)))
      f.call(f.callee("other", [], nil), [])
      b = f.fetch("i64", rec, 16)
      f.store(f.iconst("i8", 1), rec, 9)
      c = f.fetch("i64", rec, 8)
      f.ret(f.iadd(a, f.iadd(b, c)))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    loads = f.entry_block.insts.select { |i| i.op == :load }
    assert_equal [16, 8], loads.map(&:offset)
    assert_equal 3, f.entry_block.insts.count { |i| i.op == :store }
  end

  def test_a_branch_on_a_conjunction_is_a_chain_of_branches
    f = function("chain", %w[i64 i64], "i64") do |f, x, y|
      a = f.icmp("slt", x, f.iconst("i64", 10))
      c = f.icmp("sgt", f.iadd(y, f.iconst("i64", 1)), f.iconst("i64", 3))
      yes = f.label
      no = f.label
      f.brif(f.band(a, c), yes, no)
      f.switch(yes)
      f.ret(f.iconst("i64", 1))
      f.switch(no)
      f.ret(f.iconst("i64", 0))
    end
    was = [[1, 9], [20, 9], [1, 1]].map { |args| answer(f, args) }
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 4, f.blocks.size
    assert_equal %i[brif], f.blocks[0].insts.map(&:op).last(1)
    assert_equal 1, f.blocks[0].insts.count { |i| i.op == :icmp }
    assert_equal %i[iadd iconst icmp brif], f.blocks[1].insts.map(&:op)
    assert_equal was, [[1, 9], [20, 9], [1, 1]].map { |args| answer(f, args) }
    assert_equal [1, 0, 0], was
  end

  def test_a_branch_on_a_disjunction_asks_the_second_only_when_the_first_fails
    f = function("either", %w[i64 i64], "i64") do |f, x, y|
      a = f.icmp("slt", x, f.iconst("i64", 10))
      c = f.icmp("sgt", y, f.iconst("i64", 3))
      yes = f.label
      no = f.label
      f.brif(f.bor(a, c), yes, no)
      f.switch(yes)
      f.ret(f.iconst("i64", 1))
      f.switch(no)
      f.ret(f.iconst("i64", 0))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    first = f.blocks[0].insts.last
    assert_equal :brif, first.op
    assert_equal f.blocks[1].name, first.targets[1][0]
    assert_equal %i[iconst icmp brif], f.blocks[1].insts.map(&:op)
    assert_equal [1, 1, 0], [[1, 1], [20, 9], [20, 1]].map { |args| answer(f, args) }
  end

  def test_blocks_fold_away
    f = function("blocks", %w[i64], "i64") do |f, x|
      # An unreachable arm, a block that only jumps on, and a join with
      # one predecessor left once the arm is gone.
      join, (y,) = f.block(%w[i64])
      hop = f.label
      dead = f.label
      f.brif(f.iconst("i8", 1), hop, dead)
      f.switch(hop)
      f.jump(join, [x])
      f.switch(dead)
      f.jump(join, [f.iconst("i64", 7)])
      f.switch(join)
      f.ret(f.iadd(y, f.iconst("i64", 1)))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 1, f.blocks.size
    assert_equal %i[iconst iadd return], ops(f)
    assert_equal 6, answer(f, [5])
  end

  def test_a_select_between_one_value_is_that_value
    f = function("same", %w[i8 i64], "i64") do |f, c, x|
      f.ret(f.csel(c, x, x))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal %i[return], ops(f)
    assert_equal ["v1"], f.entry_block.insts.first.args
  end
def test_a_small_leaf_is_inlined_into_its_caller_and_a_cycle_is_left_as_calls
  plus = function("plus_one", %w[i64], "i64") { |f, x| f.ret(f.iadd(x, f.iconst("i64", 1))) }
  twice = function("twice_plus", %w[i64], "i64") do |f, x|
    a = f.call_val(f.callee("plus_one", %w[i64], "i64"), [x])
    f.ret(f.call_val(f.callee("plus_one", %w[i64], "i64"), [f.imul(a, f.iconst("i64", 2))]))
  end
  caller = function("caller", %w[i64], "i64") do |f, x|
    f.ret(f.call_val(f.callee("twice_plus", %w[i64], "i64"), [x]))
  end
  loop_a = function("ping", %w[i64], "i64") { |f, x| f.ret(f.call_val(f.callee("pong", %w[i64], "i64"), [x])) }
  loop_b = function("pong", %w[i64], "i64") { |f, x| f.ret(f.call_val(f.callee("ping", %w[i64], "i64"), [x])) }
  functions = [plus, twice, caller, loop_a, loop_b]
  was = Ze0::IR::Interp.new(functions).answer("caller", [20])
  Ze0::IR::Passes.inline(functions).each { |f| Ze0::IR::Passes.prepare(f, strict: true) }
  refute_includes ops(caller), :call
  refute_includes ops(twice), :call
  assert_includes ops(loop_a), :call
  assert_equal was, Ze0::IR::Interp.new(functions).answer("caller", [20])
  assert_equal 43, was
end
end
