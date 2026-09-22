# frozen_string_literal: true

require "test_helper"
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

  # A lowering that wants to drop a sequence a constant operand has
  # already decided -- the collector's write barrier, whose whole test a
  # literal answers -- asks the function what a value holds. The function
  # made its own constants, so it can say; anything else answers nil, and
  # a caller that reads nil emits what it would have emitted before.
  def test_a_function_says_which_of_its_values_are_constants
    f = function("constants", ["i64"], "i64") do |f, arg|
      eight = f.iconst("i64", 8)
      assert_equal 8, f.iconst_of(eight)
      assert_equal 8, f.iconst_of(f.iconst("i64", 8)), "the same constant is the same value"
      assert_equal 0, f.iconst_of(f.iconst("i64", 0)), "zero is a constant, not an absence"
      assert_nil f.iconst_of(arg), "a parameter holds no constant"
      assert_nil f.iconst_of(f.iadd(arg, eight)), "nor does a value computed from one"
      f.ret(f.iadd(arg, eight))
    end
    assert_equal 42, answer(f, [34])
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

  # `x * 8`, `x / 8` and `x % 8` unsigned are a shift, a shift and a
  # mask; a signed division is not, and a multiply by 6 is a multiply.
  def test_a_multiply_division_or_remainder_by_a_power_of_two_is_a_shift_or_a_mask
    f = function("reduce", %w[i64], "i64") do |f, x|
      a = f.imul(x, f.iconst("i64", 8))
      b = f.udiv(x, f.iconst("i64", 8))
      c = f.urem(x, f.iconst("i64", 8))
      d = f.sdiv(x, f.iconst("i64", 8))
      e = f.imul(x, f.iconst("i64", 6))
      f.ret(f.iadd(f.iadd(f.iadd(a, b), f.iadd(c, d)), e))
    end
    was = answer(f, [1_000_003])
    Ze0::IR::Passes.prepare(f, strict: true)

    assert_equal %i[ishl ushr band sdiv imul], ops(f).select { |op| Ze0::IR::Inst::BINOPS.include?(op) && op != :iadd }
    assert_equal was, answer(f, [1_000_003])
    assert_equal 1_000_003 * 8 + 125_000 + 3 + 125_000 + 1_000_003 * 6, was
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

  # Three tests in one are three branches, the second and third each
  # behind the one before it, whichever way the disjunction nests.
  def test_a_branch_on_three_tests_is_three_branches
    f = function("three", %w[i64 i64 i64], "i64") do |f, x, y, z|
      a = f.icmp("slt", x, f.iconst("i64", 10))
      b = f.icmp("sgt", y, f.iconst("i64", 3))
      c = f.icmp("eq", z, f.iconst("i64", 0))
      yes = f.label
      no = f.label
      f.brif(f.bor(f.bor(a, b), c), yes, no)
      f.switch(yes)
      f.ret(f.iconst("i64", 1))
      f.switch(no)
      f.ret(f.iconst("i64", 0))
    end
    args = [[1, 1, 1], [20, 9, 1], [20, 1, 0], [20, 1, 1]]
    was = args.map { |a| answer(f, a) }
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 0, ops(f).count(:bor)
    tests = f.blocks.select { |b| b.insts.last.op == :brif }
    assert_equal 3, tests.size
    assert_equal [1, 1, 1], tests.map { |b| b.insts.count { |i| i.op == :icmp } }, "one compare a branch"
    assert_equal was, args.map { |a| answer(f, a) }
    assert_equal [1, 1, 1, 0], was
  end

  # A conjunction's second test read elsewhere too stays ahead of the
  # branch chain, since the other reader needs it whichever way the
  # first test goes.
  def test_a_second_test_read_elsewhere_stays_ahead_of_the_chain
    f = function("shared", %w[i64 i64], "i64") do |f, x, y|
      a = f.icmp("slt", x, f.iconst("i64", 10))
      c = f.icmp("sgt", y, f.iconst("i64", 3))
      yes = f.label
      no = f.label
      f.brif(f.band(a, c), yes, no)
      f.switch(yes)
      f.ret(f.iconst("i64", 1))
      f.switch(no)
      f.ret(f.uextend("i64", c))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 2, f.entry_block.insts.count { |i| i.op == :icmp }, "both tests stay in the entry"
    assert_equal [1, 1, 0], [[1, 9], [20, 9], [20, 1]].map { |args| answer(f, args) }
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

  # A block joined into a predecessor laid out after it: the joined
  # instructions keep the block's place, ahead of the blocks that read
  # what they define.
  def test_a_block_joined_into_a_later_predecessor_keeps_its_place
    f = function("place", %w[i8 i8 i64], "i64") do |f, c1, c2, x|
      p, (y,) = f.block(%w[i64])
      q = f.label
      r = f.label
      b = f.label
      c = f.label
      d = f.label
      f.brif(c1, q, r)
      f.switch(b)
      z = f.iadd(y, f.iconst("i64", 1))
      f.brif(c2, c, d)
      f.switch(c)
      f.ret(z)
      f.switch(d)
      f.jump(c)
      f.switch(q)
      f.jump(p, [f.iadd(x, x)])
      f.switch(r)
      f.jump(p, [x])
      f.switch(p)
      f.jump(b)
    end
    was = [[1, 0, 5], [0, 1, 5]].map { |args| answer(f, args) }
    Ze0::IR::Passes.prepare(f, strict: true)
    adds = f.blocks.index { |blk| blk.insts.any? { |i| i.op == :iadd && i.args.include?("v3") } }
    returns = f.blocks.index { |blk| blk.insts.last.op == :return }
    assert_operator adds, :<, returns, "the join's instructions stand ahead of the block that reads them"
    assert_equal was, [[1, 0, 5], [0, 1, 5]].map { |args| answer(f, args) }
    assert_equal [11, 6], was
  end

  def test_a_select_between_one_value_is_that_value
    f = function("same", %w[i8 i64], "i64") do |f, c, x|
      f.ret(f.csel(c, x, x))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal %i[return], ops(f)
    assert_equal ["v1"], f.entry_block.insts.first.args
  end

  # `Statics`: a word the kernel keeps in a static, `bss` here, and a
  # program that answers with the words it read.
  def static(name, bytes = "\0".b * 8) = Ze0::Obj::Data.new("zr_static_#{name}", :data, bytes, align: 16)

  def answer_with(functions, data, args)
    Ze0::IR::Interp.new(functions, data: data).answer(functions[0].name, args)
  end

  def loads(f) = f.blocks.flat_map { |b| b.insts.select { |i| i.op == :load } }

  # The gate word, read out of its register at every turn of a loop
  # with a call on one arm that writes it: each read stays where it
  # is, no pass moves or merges one, and the loop's head carries no
  # word. The interpreter reads the static, which every write stores
  # to as well, and the entry from foreign code loads from.
  def test_the_gate_word_is_read_out_of_its_register
    bump = function("bump", [], nil) do |f|
      at = f.symbol_addr(f.symbol("zr_static_gates"))
      word = f.iadd(f.gates, f.iconst("i64", 1))
      f.store(word, at, region: :gates)
      f.gates_set(word)
      f.ret
    end
    f = function("tally", %w[i64], "i64") do |f, n|
      f.gates_enter(f.fetch("i64", f.symbol_addr(f.symbol("zr_static_gates")), region: :gates))
      head, (i, acc) = f.block(%w[i64 i64])
      body = f.label
      slow = f.label
      go = f.label
      done = f.label
      f.jump(head, [f.iconst("i64", 0), f.iconst("i64", 0)])
      f.switch(head)
      f.brif(f.icmp("slt", i, n), body, done)
      f.switch(body)
      sum = f.iadd(acc, f.gates)
      f.brif(f.icmp("eq", i, f.iconst("i64", 2)), slow, go)
      f.switch(slow)
      f.call(f.callee("bump", [], nil), [])
      f.jump(go)
      f.switch(go)
      f.jump(head, [f.iadd(i, f.iconst("i64", 1)), f.iadd(sum, f.gates)])
      f.switch(done)
      f.ret(acc)
    end
    was = answer_with([f, bump], [static("gates", [3].pack("q<"))], [5])
    Ze0::IR::Passes.prepare(f, strict: true)
    Ze0::IR::Passes.prepare(bump, strict: true)
    assert_equal 2, ops(f).count(:gates)
    assert_equal 1, loads(f).size, "the entry's load alone"
    assert_equal 2, f.blocks.find { |b| b.params.size == 2 }.params.size, "the head carries the counts alone"
    assert_equal %i[symbol_value gates iconst iadd store gates_set return], ops(bump)
    assert_equal was, answer_with([f, bump], [static("gates", [3].pack("q<"))], [5])
    assert_equal 3 + 3 + 3 + 3 + 3 + 4 + 4 + 4 + 4 + 4, was
  end

  # A static that is not a promoted word is still one load across a
  # call that cannot write it (`GVN`): the task pointer, over an
  # allocation. The poll word beside it is volatile: every load of it
  # stays, even two with nothing between.
  def test_a_static_that_is_not_promoted_is_numbered_and_a_volatile_word_never
    f = function("poll", [], "i64") do |f|
      at = f.symbol_addr(f.symbol("zr_static_current_task"))
      a = f.fetch("i64", at)
      b = f.fetch("i64", at, 8)
      f.call(f.callee("allocate", [], nil, effects: Ze0::IR::Effects.bit(:heap)), [])
      c = f.fetch("i64", at)
      d = f.fetch("i64", at, 8)
      e = f.fetch("i64", at)
      f.ret(f.iadd(f.iadd(a, b), f.iadd(f.iadd(c, d), e)))
    end
    allocate = function("allocate", [], nil) { |g| g.ret }
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal [0, 8, 8], loads(f).map(&:offset).sort
    assert_equal 27, answer_with([f, allocate], [static("current_task", [7, 3].pack("q<q<"))], [])
  end

  # A static's word is read again across a store to a slot, and not
  # across a call, or a store through an address the pass cannot tell
  # -- one a call answered -- which is a write to every word.
  def test_a_static_is_read_again_across_a_slot_store_and_not_across_a_call
    where = function("where", [], "i64") { |f| f.ret(f.symbol_value(f.symbol("zr_static_site_stamp"))) }
    f = function("stores", [], "i64") do |f|
      at = f.symbol_addr(f.symbol("zr_static_site_stamp"))
      f.store(f.iconst("i64", 4), at)
      a = f.fetch("i64", at)
      p = f.call_val(f.callee("where", [], "i64"), [])
      f.store(f.iconst("i64", 9), p)
      b = f.fetch("i64", at)
      f.store(f.iconst("i64", 1), f.stack_addr(f.slot(8)))
      c = f.fetch("i64", at)
      f.ret(f.iadd(a, f.iadd(b, c)))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 2, loads(f).size, "the read after the slot store is the one before it"
    assert_equal 4 + 9 + 9, answer_with([f, where], [static("site_stamp")], [])
  end

  # A call whose callee's effects leave the word alone does not make
  # the reader load it again; one whose effects may write it does. A
  # store through a pointer with a region of its own is the same as
  # such a call; one with no region is a write to everything.
  def test_a_write_that_cannot_reach_the_word_leaves_its_value_alone
    f = function("effects", %w[i64], "i64") do |f, p|
      at = f.symbol_addr(f.symbol("zr_static_site_stamp"))
      a = f.fetch("i64", at)
      f.call(f.callee("allocate", [], nil, effects: Ze0::IR::Effects.bit(:heap) | Ze0::IR::Effects.bit(:malloc)), [])
      f.store(f.iconst("i64", 1), p, 8, region: :heap)
      b = f.fetch("i64", at)
      f.call(f.callee("send", [], nil), [])
      c = f.fetch("i64", at)
      f.store(f.iconst("i64", 2), p, 16)
      d = f.fetch("i64", at)
      f.ret(f.iadd(f.iadd(a, b), f.iadd(c, d)))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal %i[symbol_value load call iconst store call load iconst store load iadd iadd iadd return], ops(f)
  end

  # `GVN`: a value computed in a dominator is read there, in either
  # order of a commutative opcode; one computed in one arm of a branch
  # is not offered to the other.
  def test_a_value_computed_by_a_dominator_is_not_computed_again
    f = function("numbering", %w[i64 i64 i8], "i64") do |f, x, y, c|
      a = f.iadd(x, y)
      left = f.label
      right = f.label
      merge, (r,) = f.block(%w[i64])
      f.brif(c, left, right)
      f.switch(left)
      f.jump(merge, [f.imul(f.iadd(y, x), f.iconst("i64", 3))])
      f.switch(right)
      f.jump(merge, [f.imul(f.iadd(x, y), f.iconst("i64", 3))])
      f.switch(merge)
      f.ret(f.iadd(r, a))
    end
    was = [[2, 3, 1], [2, 3, 0]].map { |args| answer(f, args) }
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 1, ops(f).count(:iadd) - 1, "one sum, and the return's"
    assert_equal 2, ops(f).count(:imul), "an arm's product is its own"
    assert_equal was, [[2, 3, 1], [2, 3, 0]].map { |args| answer(f, args) }
    assert_equal [20, 20], was
  end

  # A load is read again only past what cannot write its region: a
  # store to another region, a call that leaves it alone; a store to
  # its region, on any path between, makes it load again.
  def test_a_load_is_read_again_only_across_what_cannot_write_it
    f = function("reloads", %w[i64 i8], "i64") do |f, p, c|
      a = f.fetch("i64", p, 8, region: :heap)
      f.store(f.iconst("i64", 1), p, 16, region: :malloc)
      f.call(f.callee("allocate", [], nil, effects: Ze0::IR::Effects.bit(:malloc)), [])
      b = f.fetch("i64", p, 8, region: :heap)
      left = f.label
      right = f.label
      merge = f.label
      f.brif(c, left, right)
      f.switch(left)
      f.store(f.iconst("i64", 2), p, 24, region: :heap)
      f.jump(merge)
      f.switch(right)
      f.jump(merge)
      f.switch(merge)
      d = f.fetch("i64", p, 8, region: :heap)
      f.ret(f.iadd(f.iadd(a, b), d))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 2, loads(f).size, "the second load is the first; the one past the arm's store is not"
  end

  # A loop's header loads again what its body stores, whatever the
  # block before the loop loaded.
  def test_a_loop_header_loads_again_what_the_body_writes
    f = function("carried", %w[i64 i64], "i64") do |f, p, n|
      before = f.fetch("i64", p, region: :heap)
      head, (i, acc) = f.block(%w[i64 i64])
      body = f.label
      done = f.label
      f.jump(head, [f.iconst("i64", 0), before])
      f.switch(head)
      here = f.fetch("i64", p, region: :heap)
      f.brif(f.icmp("slt", i, n), body, done)
      f.switch(body)
      f.store(f.iadd(here, f.iconst("i64", 1)), p, region: :heap)
      f.jump(head, [f.iadd(i, f.iconst("i64", 1)), f.iadd(acc, here)])
      f.switch(done)
      f.ret(f.iadd(acc, here))
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    assert_equal 2, loads(f).size
  end

  # `LICM`: what a loop computes the same at every turn -- a product of
  # two values from outside it, a load of a word the loop cannot write
  # -- is computed once, in a block before the loop's head, and the
  # loop's turns read the values.
  def test_what_a_loop_computes_the_same_at_every_turn_is_computed_before_it
    f = function("hoisted", %w[i64 i64], "i64") do |f, n, m|
      word = f.symbol_addr(f.symbol("zr_static_word"))
      stamp = f.symbol_addr(f.symbol("zr_static_site_stamp"))
      head, (i, acc) = f.block(%w[i64 i64])
      body = f.label
      done = f.label
      f.jump(head, [f.iconst("i64", 0), f.iconst("i64", 0)])
      f.switch(head)
      f.brif(f.icmp("slt", i, n), body, done)
      f.switch(body)
      f.store(i, stamp)
      step = f.iadd(f.imul(m, f.iconst("i64", 3)), f.fetch("i64", word))
      f.jump(head, [f.iadd(i, f.iconst("i64", 1)), f.iadd(acc, step)])
      f.switch(done)
      f.ret(acc)
    end
    data = [static("word", [7].pack("q<")), static("site_stamp")]
    was = answer_with([f], data, [4, 5])
    Ze0::IR::Passes.prepare(f, strict: true)
    loops = f.analysis.loops
    assert_equal 1, loops.size
    %i[imul load].each do |op|
      at = f.blocks.find { |b| b.insts.any? { |i| i.op == op } }
      refute_includes loops[0].body, at.name, "the #{op} is before the loop"
    end
    assert_equal was, answer_with([f], data, [4, 5])
    assert_equal 88, was
  end

  # A compare that only a branch reads stays in the loop, where the
  # backend folds it into the branch; the sum it guards, which the arm
  # reads, moves out.
  def test_a_test_only_a_branch_reads_stays_in_the_loop
    f = function("tested", %w[i64 i64], "i64") do |f, n, m|
      head, (i, acc) = f.block(%w[i64 i64])
      body = f.label
      big = f.label
      small = f.label
      done = f.label
      f.jump(head, [f.iconst("i64", 0), f.iconst("i64", 0)])
      f.switch(head)
      f.brif(f.icmp("slt", i, n), body, done)
      f.switch(body)
      f.brif(f.icmp("sgt", m, f.iconst("i64", 2)), big, small)
      f.switch(big)
      f.jump(head, [f.iadd(i, f.iconst("i64", 1)), f.iadd(acc, f.iadd(m, f.iconst("i64", 4)))])
      f.switch(small)
      f.jump(head, [f.iadd(i, f.iconst("i64", 1)), acc])
      f.switch(done)
      f.ret(acc)
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    body = f.analysis.loops[0].body
    inside = f.blocks.select { |b| body.include?(b.name) }.flat_map(&:insts).map(&:op)
    assert_equal 2, inside.count(:icmp), "the loop's own test and the branch's"
    assert_equal 3, inside.count(:iadd), "two counts and the accumulation; `m + 4` moved out"
    assert_equal [21, 0], [[3, 3], [3, 1]].map { |args| answer(f, args) }
  end

  # A load the loop's test guards -- a word behind a pointer the head
  # tests for null -- stays behind it, and a load of the volatile
  # region stays where it is; a word a store before the loop proves is
  # there is read before it.
  def test_a_load_a_test_guards_and_a_volatile_load_stay_in_the_loop
    f = function("guarded", %w[i64 i64], "i64") do |f, p, r|
      poll = f.symbol_addr(f.symbol("zr_static_current_task"))
      f.store(f.iconst("i64", 1), r, 16, region: :malloc)
      head, (q, acc) = f.block(%w[i64 i64])
      body = f.label
      done = f.label
      f.jump(head, [p, f.iconst("i64", 0)])
      f.switch(head)
      f.brif(f.icmp("ne", q, f.iconst("i64", 0)), body, done)
      f.switch(body)
      pending = f.fetch("i64", poll, 8)
      sum = f.iadd(f.iadd(f.fetch("i64", q, region: :heap), pending), f.fetch("i64", r, 16, region: :malloc))
      f.jump(head, [f.fetch("i64", q, 8, region: :heap), f.iadd(acc, sum)])
      f.switch(done)
      f.ret(acc)
    end
    Ze0::IR::Passes.prepare(f, strict: true)
    loops = f.analysis.loops
    assert_equal 1, loops.size
    inside, outside = loads(f).partition { |i| loops[0].body.include?(f.blocks.find { |b| b.insts.include?(i) }.name) }
    assert_equal [16], outside.map(&:offset), "the stored word"
    assert_equal 3, inside.size, "the poll word and the two behind the tested pointer"
  end

  # An address that reaches a call, or a store of part of the word,
  # keeps every load of the word.
  def test_a_word_whose_address_escapes_or_that_is_written_in_part_keeps_its_loads
    escapes = function("escapes", [], "i64") do |f|
      stamp = f.symbol_addr(f.symbol("zr_static_site_stamp"))
      a = f.fetch("i64", stamp)
      f.call(f.callee("take", %w[i64], nil), [stamp])
      f.ret(f.iadd(a, f.fetch("i64", stamp)))
    end
    part = function("part", [], "i64") do |f|
      stamp = f.symbol_addr(f.symbol("zr_static_site_stamp"))
      a = f.fetch("i64", stamp)
      f.store(f.iconst("i32", 1), stamp)
      f.ret(f.iadd(a, f.fetch("i64", stamp)))
    end
    [escapes, part].each do |f|
      Ze0::IR::Passes.prepare(f, strict: true)
      assert_equal 2, loads(f).size, f.name
    end
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

  # A leaf that keeps a value in a slot of its own is inlined with the
  # slot made the caller's; one whose slots are large stays a call.
  def test_a_leaf_with_a_small_slot_is_inlined_and_a_large_one_stays_a_call
    through = function("through_slot", %w[i64], "i64") do |f, x|
      at = f.stack_addr(f.slot(8))
      f.store(x, at)
      f.ret(f.iadd(f.fetch("i64", at), f.iconst("i64", 1)))
    end
    buffer = function("through_buffer", %w[i64], "i64") do |f, x|
      at = f.stack_addr(f.slot(Ze0::IR::Passes::Inline::SLOT_BYTES + 8))
      f.store(x, at)
      f.ret(f.fetch("i64", at))
    end
    caller = function("caller", %w[i64], "i64") do |f, x|
      a = f.call_val(f.callee("through_slot", %w[i64], "i64"), [x])
      f.ret(f.iadd(a, f.call_val(f.callee("through_buffer", %w[i64], "i64"), [x])))
    end
    functions = [through, buffer, caller]
    Ze0::IR::Passes.inline(functions).each { |f| Ze0::IR::Passes.prepare(f, strict: true) }

    assert_equal 1, ops(caller).count(:call)
    assert_equal 1, caller.slots.size
    assert_equal 41, Ze0::IR::Interp.new(functions).answer("caller", [20])
  end
end
