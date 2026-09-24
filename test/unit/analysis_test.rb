# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/ir/analysis"
require_relative "../../lib/zr/ir/verify"

# Tests the analysis cache of a function: predecessors, blocks in reverse
# postorder, the dominator tree and the natural loops. The cache is
# built once and kept until a pass reports that the function changed.
# If a pass edits the graph and does not report it, the strict check
# finds it: it builds the analysis again and compares.
class AnalysisTest < Minitest::Test
  Analysis = Zr::IR::Analysis

  # entry -> head; head -> body | done; body -> head; done -> ret. A
  # diamond hangs off body: body -> left | right -> join -> head.
  def looped
    f = Zr::IR::Function.new("looped", %w[i64], "i64")
    n = f.args[0]
    head, (i,) = f.block(%w[i64])
    body = f.label
    left = f.label
    right = f.label
    join, (step,) = f.block(%w[i64])
    done = f.label
    f.jump(head, [f.iconst("i64", 0)])
    f.switch(head)
    f.brif(f.icmp("slt", i, n), body, done)
    f.switch(body)
    f.brif(f.icmp("eq", f.band(i, f.iconst("i64", 1)), f.iconst("i64", 0)), left, right)
    f.switch(left)
    f.jump(join, [f.iconst("i64", 1)])
    f.switch(right)
    f.jump(join, [f.iconst("i64", 2)])
    f.switch(join)
    f.jump(head, [f.iadd(i, step)])
    f.switch(done)
    f.ret(i)
    [f, { head: head, body: body, left: left, right: right, join: join, done: done }]
  end

  def test_predecessors_order_and_dominators
    f, b = looped
    a = f.analysis

    assert_same a, f.analysis, "the analysis is kept"
    assert_equal [f.entry_block.name, b[:join]].sort, a.preds.fetch(b[:head]).sort
    assert_equal [b[:left], b[:right]].sort, a.preds.fetch(b[:join]).sort
    assert_equal f.entry_block.name, a.rpo.first.name
    assert_equal f.blocks.size, a.rpo.size
    assert_operator a.rpo.index { |x| x.name == b[:head] }, :<, a.rpo.index { |x| x.name == b[:body] }
    assert_nil a.idom.fetch(f.entry_block.name)
    assert_equal b[:head], a.idom.fetch(b[:body])
    assert_equal b[:head], a.idom.fetch(b[:done])
    assert_equal b[:body], a.idom.fetch(b[:join])
    assert a.dominates?(b[:head], b[:join])
    assert a.dominates?(b[:body], b[:left])
    refute a.dominates?(b[:left], b[:join])
    refute a.dominates?(b[:done], b[:body])
    assert a.dominates?(b[:head], b[:head])
  end

  def test_the_natural_loop_has_its_header_body_and_depth
    f, b = looped
    loops = f.analysis.loops

    assert_equal 1, loops.size
    loop = loops.first
    assert_equal b[:head], loop.header
    assert_equal [b[:head], b[:body], b[:left], b[:right], b[:join]].sort, loop.body.sort
    assert_equal 1, loop.depth
    assert_equal 1, f.analysis.depth_of(b[:join])
    assert_equal 0, f.analysis.depth_of(b[:done])
  end

  def test_uses_count_every_read_and_a_jump_argument
    f, b = looped
    uses = f.analysis.uses
    param = ->(name) { f.blocks.find { |x| x.name == name }.params[0][0] }

    assert_equal 1, uses.fetch(f.args[0]), "n is read by the compare"
    assert_equal 4, uses.fetch(param.call(b[:head])), "i is read by the compare, the mask, the add and the return"
    assert_equal 1, uses.fetch(param.call(b[:join])), "step is read by the add"
  end

  def test_reported_change_rebuilds_the_analysis
    f, b = looped
    was = f.analysis
    extra = f.label
    f.switch(extra, open: true)
    f.jump(b[:done])
    f.changed!(:cfg)

    refute_same was, f.analysis
    assert_includes f.analysis.preds.fetch(b[:done]), extra
  end

  def test_unreported_change_fails_the_strict_check
    f, b = looped
    f.analysis.preds
    extra = f.label
    f.switch(extra, open: true)
    f.jump(b[:done])

    e = assert_raises(Zr::IR::Verify::Error) { Zr::IR::Verify.check(f, strict: true) }
    assert_match(/stale/, e.message)

    f.changed!(:cfg)
    assert_same f, Zr::IR::Verify.check(f, strict: true)
  end

  def test_instruction_change_keeps_graph_and_drops_uses
    f, = looped
    a = f.analysis
    idom = a.idom
    uses = a.uses
    f.changed!(:insts)

    assert_same idom, f.analysis.idom, "the graph did not move"
    refute_same uses, f.analysis.uses
  end
end
