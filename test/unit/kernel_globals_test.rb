# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/paths"

# Each `G_*` constant of the kernel names one slot of the globals table
# (`zr_globals`). Two names on one slot overwrite each other: method
# coverage once replaced `Process.argv0` with its rows.
class KernelGlobalsTest < Minitest::Test
  def test_each_global_has_its_own_slot_in_the_table
    slots = Dir[File.join(Zr::Paths::RUNTIME, "kernel/**/*.rb")].flat_map do |file|
      File.read(file).scan(/^\s*(G_[A-Z0-9_]+) = (\d+)$/).map { |name, slot| [name, Integer(slot)] }
    end.to_h
    count = slots.delete("G_COUNT")

    shared = slots.group_by(&:last).select { |_, names| names.size > 1 }.transform_values { |names| names.map(&:first) }
    assert_empty shared
    assert_operator slots.values.max, :<, count
  end
end
