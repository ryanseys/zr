# frozen_string_literal: true

require "test_helper"
require "prism"
require_relative "../../lib/zr/hir"

# Each dispatcher over HIR nodes has an arm for each kind of node, or this
# test states why it has none. A new kind of node fails here until each
# dispatcher has an arm or a reason for it. The test reads the first `case`
# of each dispatcher with Prism, so it builds nothing.
class HirDispatchTest < Minitest::Test
  # Every kind of node: each class below Hir that is a Node.
  NODES = Zr::Hir.constants.select do |name|
    kind = Zr::Hir.const_get(name)
    kind.is_a?(Class) && kind < Zr::Hir::Node
  end.sort.freeze

  # The kinds that stand only inside other nodes. The arm of the owner
  # reads them, so no dispatcher needs one.
  PARTS = %i[Block BlockPass HashSplat MultiTarget Params Program Rescue Splat Unit].freeze

  SLOT = "only the lowering makes a Slot, for a value that it put in a record slot"

  # The kinds that `Lower::Scope#staging` leaves to its `else base`: none
  # of their fields holds a node that stages in this scope's records.
  STAGES_NOTHING = {
    "it holds only names, numbers or text" =>
      %i[Activations Alias BackRef Core Cover CvarRead ExtInit FrozenString GvarAlias GvarRead IvarRead Literal Local
         RegexpLit SelfRef Stop Trace Undef UsingDefaults],
    "it is a jump with no value" => %i[Redo RedoPoint Retry],
    "its one node is a literal" => %i[PathLiteral],
    "its block or unit has records of its own" => %i[Require ZSuper]
  }.flat_map { |reason, kinds| kinds.map { |kind| [kind, reason] } }.to_h.freeze

  # Each dispatcher: its file, its method, and the kinds without an arm,
  # each with the reason.
  DISPATCHERS = [
    ["lib/zr/lower/function/expressions.rb", :expr, {}],
    ["lib/zr/machine/host/walk/code.rb", :code, { Slot: SLOT }],
    ["lib/zr/eval/interpreter/tree.rb", :walk,
     { Slot: SLOT, Activations: "a string compiled at run time has no program prelude" }],
    ["test/support/hir_dump.rb", :node, {}],
    ["lib/zr/lower/scope.rb", :staging, STAGES_NOTHING]
  ].freeze

  def test_parts_and_reasons_name_kinds_of_node
    named = PARTS + DISPATCHERS.flat_map { |_, _, gaps| gaps.keys }

    assert_empty named - NODES
  end

  DISPATCHERS.each do |file, method, gaps|
    define_method(:"test_#{method}_has_an_arm_or_a_reason_for_each_kind") do
      arms = arms(file, method)

      assert_empty NODES - PARTS - arms - gaps.keys, "#{file}##{method} has no arm for these kinds"
      assert_empty arms & gaps.keys, "#{file}##{method} has an arm for these kinds; drop their reasons"
    end
  end

  private

  # The kinds of node that the first `case` of `method` in `file` names in
  # its `when` arms.
  def arms(file, method)
    tree = Prism.parse_file(File.join(ROOT, file)).value
    definition = tree.breadth_first_search { |node| node.is_a?(Prism::DefNode) && node.name == method }
    dispatch = definition.body.breadth_first_search { |node| node.is_a?(Prism::CaseNode) }
    dispatch.conditions.flat_map(&:conditions).filter_map do |condition|
      condition.name if condition.is_a?(Prism::ConstantPathNode) || condition.is_a?(Prism::ConstantReadNode)
    end
  end
end
