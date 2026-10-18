# frozen_string_literal: true

require "test_helper"
require "prism"
require_relative "../../lib/zr/paths"
require_relative "../../lib/zr/lock_plan"

# Every piece of the kernel's shared state has a lock plan
# (`Zr::LockPlan`): each static and global that a kernel file declares,
# and each slot of the globals table. A static that native threads, or
# threads with no GVL, would share by accident breaks only under
# contention, so the plan names it before any thread can reach it.
class LockPlanTest < Minitest::Test
  # The names that the kernel declares, from its own source: the first
  # argument of each `Machine.static` and `Machine.global`, and each
  # `G_*` slot constant.
  class Declared < Prism::Visitor
    attr_reader :names

    def initialize
      super
      @names = Set.new
    end

    def visit_call_node(node)
      if node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Machine && %i[static global].include?(node.name)
        name = node.arguments&.arguments&.first
        @names << name.unescaped if name.is_a?(Prism::SymbolNode)
      end
      super
    end

    def visit_constant_write_node(node)
      @names << node.name.to_s if node.name.start_with?("G_") && node.name != :G_COUNT && node.value.is_a?(Prism::IntegerNode)
      super
    end
  end

  def declared
    @declared ||= Dir[File.join(Zr::Paths::RUNTIME, "kernel/**/*.rb")].each_with_object(Declared.new) do |file, visitor|
      Prism.parse_file(file).value.accept(visitor)
    end.names
  end

  def test_every_static_global_and_slot_of_the_kernel_has_a_plan
    assert_empty declared.reject { |name| Zr::LockPlan[name] }.sort
  end

  def test_every_plan_names_state_that_the_kernel_declares
    assert_empty Zr::LockPlan::ENTRIES.keys.reject { |name| declared.include?(name) }.sort
  end

  def test_each_name_has_one_plan
    names = Zr::LockPlan::ROWS.flat_map(&:last)
    assert_empty names.tally.select { |_, n| n > 1 }.keys
  end

  def test_each_plan_takes_a_known_rule
    Zr::LockPlan::ENTRIES.each do |name, entry|
      assert_includes Zr::LockPlan::NOW, entry.now, name
      assert_includes Zr::LockPlan::FREE, entry.free, name
    end
  end

  # A GVL handoff saves and restores exactly the words that each thread
  # keeps for itself (kernel/gvl.rb), as a fiber switch does.
  def test_the_per_thread_words_are_the_running_fiber_its_task_and_its_roots
    assert_equal %w[current_fiber current_task kroots], Zr::LockPlan.per_thread
  end
end
