# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/hir"

# The HIR of each `test/hir/<name>.rb`, dumped as S-expressions, held
# byte for byte in `<name>.hir`; `ZE0_BLESS=1` rewrites.
class HirTest < Minitest::Test
  Dir[File.join(ROOT, "test/hir/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      got = Ze0::Hir::Dump.program(Ze0::Hir.build(File.read(rb), "#{name}.rb"))
      want = rb.sub(/\.rb\z/, ".hir")
      if ENV["ZE0_BLESS"]
        File.write(want, got)
      else
        assert File.file?(want), "#{want} is missing (ZE0_BLESS=1 records it)"
        assert_equal File.read(want), got
      end
    end
  end

  # The three nodes no fixture can hold. `Trace` is placed only where
  # the program arms line events and `Cover` only where it names
  # Coverage, neither of which `Hir.build` has a way to ask for, and
  # `Slot` is the lowering's own node for a receiver it has already
  # evaluated -- `Hir::Build` never writes one. Their arms are asked for
  # here, so that all of `Hir`'s nodes are covered between the two.
  def test_the_nodes_no_program_of_ours_holds
    assert_equal "(trace line)", dump(Ze0::Hir::Trace.new(:line, 1))
    assert_equal "(cover 7)", dump(Ze0::Hir::Cover.new(7, 1))
    assert_equal "(slot 3)", dump(Ze0::Hir::Slot.new(3, 1))
  end

  private

  def dump(node)
    lines = []
    Ze0::Hir::Dump.node(node, 0, lines)
    lines.join("\n")
  end
end
