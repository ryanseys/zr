# frozen_string_literal: true

require "test_helper"
require "zr/runtime"
require "zr/native/build"

# The kernel description a program carries for its evals, one per OS
# layer. A stale one is a miscompile, so the check writes each again and
# demands the same bytes. `ZR_BLESS=1` rewrites them.
class DescriptionTest < Minitest::Test
  # One target per OS layer that is its own.
  TARGETS = Zr::Target.all.select { |target| target.os_layer == target.os.to_s }.uniq(&:os_layer)

  def path(target) = File.join(ROOT, "runtime/ext/os", target.os_layer, "zr_description.rb")

  # The kernel lowered for this file alone, and never `Zr.runtime`,
  # which the whole process shares. `Native::Build.lower` lets the
  # shared one's IR go as soon as the runtime object is named
  # (lib/zr/native/build.rb:105), and it does so on a warm cache too,
  # where nothing was lowered to let go of. What the IR answered is
  # refused from then on rather than lowered again, which is right for
  # a build and leaves a test that reads it holding nothing.
  def kernel(target) = Zr::Runtime.new(target).unit

  # `immediate?` is `zr_special_p` (runtime/kernel/value.rb) asked at compile
  # time, so that a lowering can drop a test a word it made has already
  # answered. The two must agree, and the kernel's own constants are
  # what says whether they do.
  def test_the_description_calls_a_word_immediate_where_the_kernel_would
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

    define_method("test_the_#{target.os_layer}_description_answers_as_its_kernel_unit_does") do
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

  # A build before this file left it nothing to read: under seed 55324
  # on 2026-09-19 the darwin row failed with "the runtime's IR was
  # released", and every other seed passed. This runs the build first,
  # so the order that broke it is the order it is held to.
  def test_a_build_leaves_this_file_a_kernel_to_read
    Zr::Native::Build.lower("p 1\n", "description_test.rb", target: TARGETS.first)
    assert_predicate Zr::Machine::Description.of(kernel(TARGETS.first)).defs, :any?
  end
end
