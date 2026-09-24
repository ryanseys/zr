# frozen_string_literal: true

require "test_helper"
require "zr/runtime"
require "zr/native/build"

# Tests the kernel description that a program includes for eval support.
# There is one description for each OS layer. A stale description causes
# a miscompile, so the test writes each one again and requires the same
# bytes. `ZR_BLESS=1` writes them again.
class DescriptionTest < Minitest::Test
  # One target per OS layer that is its own.
  TARGETS = Zr::Target.all.select { |target| target.os_layer == target.os.to_s }.uniq(&:os_layer)

  def path(target) = File.join(ROOT, "runtime/ext/os", target.os_layer, "zr_description.rb")

  # Lowers the kernel for this file only. Do not use `Zr.runtime`: the
  # whole process shares it, and `Native::Build.lower` releases its IR
  # when the runtime object is known (lib/zr/native/build.rb:105). It
  # does this also on a warm cache. After that, a read of the IR is
  # refused and not lowered again. That is correct for a build, but a
  # test that reads the IR then gets nothing.
  def kernel(target) = Zr::Runtime.new(target).unit

  # `immediate?` is `zr_special_p` (runtime/kernel/value.rb) at compile
  # time. A lowering uses it to remove a test when the result is already
  # known. The two must agree, and the kernel's own constants decide.
  def test_description_immediate_matches_kernel_special_check
    carried = Zr::Machine::Description.parse(File.read(path(TARGETS.first))[/<<~ROWS\n(.*?)^\s*ROWS$/m, 1].gsub(/^ +/, ""))
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
    define_method("test_the_#{target.os_layer}_description_matches_its_kernel") do
      text = IO.popen([RbConfig.ruby, "-I#{File.join(ROOT, "lib")}", File.join(ROOT, "test/support/generators/description.rb"), target.triple], &:read)
      assert $?.success?, "test/support/generators/description.rb failed"

      if ENV["ZR_BLESS"] == "1"
        File.write(path(target), text)
        skip "blessed #{path(target)}"
      end
      assert_equal File.read(path(target)), text, "#{path(target)} is stale (ZR_BLESS=1 to accept)"
    end

    define_method("test_the_#{target.os_layer}_description_equals_the_lowered_kernel_unit") do
      unit = kernel(target)
      carried = Zr::Machine::Description.parse(File.read(path(target))[/<<~ROWS\n(.*?)^\s*ROWS$/m, 1].gsub(/^ +/, ""))
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
end
