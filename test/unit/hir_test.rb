# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# Dumps the HIR of each `test/hir/<name>.rb` as S-expressions and
# compares it byte for byte with `<name>.hir`. `ZR_BLESS=1` writes the
# `.hir` files again.
class HirTest < Minitest::Test
  Dir[File.join(ROOT, "test/hir/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      got = Zr::Hir::Dump.program(Zr::Hir.build(File.read(rb), "#{name}.rb"))
      want = rb.sub(/\.rb\z/, ".hir")
      if Checks.bless?
        File.write(want, got)
      else
        assert File.file?(want), "#{want} is missing (ZR_BLESS=1 records it)"
        assert_equal File.read(want), got
      end
    end
  end

  # Tests the three nodes that no fixture can contain. `Hir::Build` adds
  # `Trace` only where the program arms line events, and `Cover` only
  # where it refers to Coverage. `Hir.build` has no option for either.
  # `Slot` is a lowering node for a receiver that is already evaluated,
  # and `Hir::Build` never makes one. With this test and the fixtures,
  # the tests cover all `Hir` nodes.
  def test_dump_of_nodes_that_no_fixture_contains
    assert_equal "(trace line)", dump(Zr::Hir::Trace.new(:line, 1))
    assert_equal "(cover 7)", dump(Zr::Hir::Cover.new(7, 1))
    assert_equal "(slot 3)", dump(Zr::Hir::Slot.new(3, 1))
  end

  private

  def dump(node)
    lines = []
    Zr::Hir::Dump.node(node, 0, lines)
    lines.join("\n")
  end
end
