# frozen_string_literal: true

require "test_helper"
require "zr/runtime"
require "zr/native/build"

# Tests the kernel description that a program includes for eval support.
# A build writes it into the store from the kernel it lowered
# (`Runtime#carry_description!`), so it cannot be stale. The test checks
# that the carried file gives back each row of the kernel.
class DescriptionTest < Minitest::Test
  # One target per OS layer that is its own.
  TARGETS = Zr::Target.all.select { |target| target.os_layer == target.os.to_s }.uniq(&:os_layer)

  # Lowers the kernel for this file only. Do not use `Zr.runtime`: the
  # whole process shares it, and `Native::Build.lower` releases its IR
  # when the runtime object is known (lib/zr/native/build.rb:105). It
  # does this also on a warm cache. After that, a read of the IR is
  # refused and not lowered again. That is correct for a build, but a
  # test that reads the IR then gets nothing.
  def kernel(target) = Zr::Runtime.new(target).unit

  # The description as eval support reads it: the carried Ruby file of
  # the kernel's rows, parsed back.
  def carried(unit)
    file = Zr::Machine::Description.carried(Zr::Machine::Description.of(unit).to_text)
    Zr::Machine::Description.parse(file[/<<~ROWS\n(.*?)^\s*ROWS$/m, 1].gsub(/^ +/, ""))
  end

  # `immediate?` is `zr_special_p` (runtime/kernel/value.rb) at compile
  # time. A lowering uses it to remove a test when the result is already
  # known. The two must agree, and the kernel's own constants decide.
  def test_description_immediate_matches_kernel_special_check
    carried = carried(kernel(TARGETS.first))
    special = ->(w) { (w & 7) != 0 || w == carried.const_for("QFALSE") || w == carried.const_for("QNIL") }

    words = %w[QFALSE QNIL QTRUE QUNDEF].map { |name| carried.const_for(name) }
    words += [1, 3, 85, -1 & ((1 << 64) - 1)]                   # fixnums, odd whatever the value
    words << ((12 << 8) | carried.const_for("SYMBOL_TAG"))      # a symbol
    words << carried.const_for("FLONUM_ZERO")                   # a flonum
    words += [16, 4096, 1 << 40]                                # and cells, which are none of these

    words.each do |word|
      assert_equal special.call(word), carried.immediate?(word), format("%#x", word)
    end

    assert carried.immediate?(carried.const_for("QNIL")), "nil is an immediate"
    refute carried.immediate?(1 << 40), "an aligned word above QNIL is a cell"
  end

  TARGETS.each do |target|
    define_method("test_the_#{target.os_layer}_description_equals_the_lowered_kernel_unit") do
      unit = kernel(target)
      carried = carried(unit)
      live = Zr::Machine::Description.of(unit)

      assert_equal live.defs.keys.sort, carried.defs.keys.sort
      live.defs.each do |name, d|
        assert_equal [d.params, d.ret, d.effects],
                     [carried.def_for(name).params, carried.def_for(name).ret, carried.def_for(name).effects], name
      end
      assert live.defs.values.all? { |d| d.effects.is_a?(Integer) }, "every def has its effects"
      live.consts.each { |name, value| assert_equal value, carried.const_for(name), name }
      live.structs.each do |name, layout|
        assert_equal [layout.fields, layout.size, layout.align],
                     [carried.struct_for(name).fields, carried.struct_for(name).size, carried.struct_for(name).align], name
      end
    end
  end

  # A build that runs first releases the shared IR. Seed 55324 found this:
  # the darwin test failed with "the runtime's IR was released". This test
  # runs a build first, so that it always checks that order.
  def test_a_build_leaves_this_file_a_kernel_to_read
    Zr::Native::Build.lower("p 1\n", "description_test.rb", target: TARGETS.first)
    assert_predicate Zr::Machine::Description.of(kernel(TARGETS.first)).defs, :any?
  end

  ROWS = <<~ROWS
    d zr_a Value v:Value
    e zr_a 3
    c QNIL 8
    s Pair 16 8 left:0:Value right:8:Value
  ROWS

  # A cache of lowered code keeps the rows that a piece read
  # (`EvalCache`), so a kernel edit that the piece does not read keeps it.
  def test_record_gives_each_row_that_the_lookups_read
    description = Zr::Machine::Description.parse(ROWS)

    reads = description.record do
      description.def_for("zr_a")
      description.const_for("QNIL")
      description.struct_for("Pair")
      description.def_for("zr_missing")
    end

    assert_equal({ [:d, "zr_a"] => "d zr_a Value v:Value e 3", [:c, "QNIL"] => "c QNIL 8",
                   [:s, "Pair"] => "s Pair 16 8 left:0:Value right:8:Value", [:d, "zr_missing"] => nil }, reads)
    assert_nil description.record { nil }.first
  end

  def test_rows_change_only_with_a_row_that_was_read
    reads = Zr::Machine::Description.parse(ROWS).then { |d| d.record { d.def_for("zr_a") && d.def_for("zr_new") } }
    added = Zr::Machine::Description.parse("#{ROWS}d zr_b Value\ne zr_b 0\n")
    changed = Zr::Machine::Description.parse(ROWS.sub("e zr_a 3", "e zr_a 1"))
    defined = Zr::Machine::Description.parse("#{ROWS}d zr_new Value\ne zr_new 0\n")

    assert_equal reads, added.rows(reads)
    refute_equal reads, changed.rows(reads)
    refute_equal reads, defined.rows(reads)
  end
end
