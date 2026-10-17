# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# `Zr::Binary.running?` tells zr's own code that a zr binary runs it, not
# CRuby. A build appends lib/zr/runtime/lib/zr/binary.rb to lib/zr/binary.rb
# (`Hir::Build::Loader.tails`), and that file sets `Zr::Binary::BUILT`.
# RbConfig cannot tell them apart: a binary's RbConfig names the launcher
# that started it, `ruby` under test-all.
class BinaryRunningTest < Minitest::Test
  BINARY = File.expand_path("../../lib/zr/binary.rb", __dir__)
  TAIL = File.expand_path("../../lib/zr/runtime/lib/zr/binary.rb", __dir__)

  def test_cruby_does_not_count_as_a_binary
    refute_predicate Zr::Binary, :running?
    refute Zr::Binary.const_defined?(:BUILT, false)
  end

  def test_a_build_of_the_file_ends_with_the_mark
    program = Zr::Hir.build("require #{BINARY.dump}\n", "binary_running_test.rb")
    unit = program.units.find { it.file == BINARY } or flunk "the build has no unit of #{BINARY}"
    assert_includes requires(unit.body), TAIL
    assert program.units.any? { it.file == TAIL }, "the build carries the mark's file"
  end

  def test_the_mark_sets_built
    tree = Prism.parse_file(TAIL).value
    write = tree.statements.body.last
    assert_kind_of Prism::ConstantPathWriteNode, write
    assert_equal "Zr::Binary::BUILT", write.target.slice
  end

  private

  # The paths of the requires in a unit's body.
  def requires(node, out = [])
    case node
    when Array then node.each { requires(it, out) }
    when Zr::Hir::Node
      out << node.path if node.is_a?(Zr::Hir::Require)
      Zr::Hir.each_child(node) { requires(it, out) }
    end
    out
  end
end
