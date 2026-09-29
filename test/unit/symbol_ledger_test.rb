# frozen_string_literal: true

require "test_helper"
require "zr/machine/lower"

# The runtime's symbol table ends in pads, and in a checkout it starts
# from the ledger of the last build: each name keeps its id, and a new
# name takes a pad, so the code of the functions that do not use it stays
# the same, and the ids after the table do not move.
class SymbolLedgerTest < Minitest::Test
  Symbols = Zr::Machine::Symbols

  def test_a_fresh_table_numbers_names_in_order_and_ends_in_pads
    table = Symbols.new
    %w[a b c].each { |name| table.id(name) }
    table.pad!

    assert_equal %w[a b c], table.names.first(3)
    assert_equal Symbols::BLOCK, table.names.size
    assert(table.names.drop(3).all?(&:nil?))
  end

  def test_a_ledger_keeps_ids_and_a_new_name_takes_a_pad
    ledger = ["a", nil, "c", nil]
    table = Symbols.new(ledger, fill: true)

    assert_equal 2, table.id("c")
    assert_equal 0, table.id("a")
    assert_equal 1, table.id("new"), "the first free id"
    assert_equal 3, table.id("newer")
    assert_equal 4, table.id("newest"), "after the table, when no id is free"
  end

  def test_a_table_made_from_another_appends_after_its_pads
    runtime = Symbols.new(["a", nil, nil])
    assert_equal 3, runtime.id("eval_name"), "only the runtime's own table fills its pads"
  end

  def test_used_names_only_are_the_next_ledger
    table = Symbols.new(%w[a b c], fill: true)
    table.id("c")
    table.id("d")

    assert_equal [nil, nil, "c", "d"], table.names.each_with_index.map { |name, i| name if table.used?(i) }
  end
end
