# frozen_string_literal: true

require_relative "helper"
require "stringio"
require_relative "../../lib/ze0/ir/interp"
require_relative "../../lib/ze0/machine/lower"
require_relative "../native/fixtures"

# The second oracle: every program the kernel dialect can write, answered
# by `IR::Interp` instead of by a binary. The compiled road and this one
# read the same `.stdout`, so a miscompile in `IR::Arm64` shows up as a
# disagreement rather than as a wrong answer with nowhere to look.
class InterpTest < Minitest::Test
  # Machine code has no IR to interpret, so a program that calls some is
  # refused by name. `switch.rb` is the only one.
  RAW = %w[switch].freeze

  def answers(functions, data, raw, argv)
    out = StringIO.new
    status = Ze0::IR::Interp.new(functions, data: data, raw: raw, out: out, err: out).run(argv)
    [status, out.string]
  end

  Ze0::Native::Fixtures::NAMES.each do |name|
    define_method("test_native_#{name}") do
      functions, data = Ze0::Native::Fixtures.build(name)
      status, out = answers(functions, data, [], [name])
      assert_equal 0, status, "#{name} exited #{status}"
      assert_equal File.binread(File.join(ROOT, "test/native/#{name}.stdout")), out
    end
  end

  Dir[File.join(ROOT, "test/zr/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_zr_#{name}") do
      functions, data, raw = Ze0::Machine.compile(File.read(rb), rb)
      if RAW.include?(name)
        e = assert_raises(Ze0::IR::Interp::Refused) { answers(functions, data, raw, [name]) }
        assert_includes e.message, "machine code, not IR"
      else
        status, out = answers(functions, data, raw, [name])
        assert_equal 0, status, "#{name} exited #{status}"
        assert_equal File.binread(rb.sub(/\.rb\z/, ".stdout")), out
      end
    end
  end

  Dir[File.join(ROOT, "test/zr/units/*/")].sort.each do |unit|
    name = File.basename(unit)
    define_method("test_zr_unit_#{name}") do
      functions, data, raw = Ze0::Machine.compile_unit(Dir[File.join(unit, "*.rb")].sort)
      status, out = answers(functions, data, raw, [name])
      assert_equal 0, status, "#{name} exited #{status}"
      assert_equal File.binread(File.join(unit, "stdout")), out
    end
  end

  # The collector under stress, the case the compiled road also runs: a
  # program that drops a root out of its record must abort.
  def test_a_missed_root_aborts
    source = File.read(File.join(ROOT, "test/zr/gc.rb"))
    bad = source.sub("    Machine.store64(rec, 24, leaf)\n    leaf = 0\n", "    Machine.store64(rec, 24, 0)\n")
                .sub("    Machine.store64(pair, 8, Machine.load64(rec, 24))", "    Machine.store64(pair, 8, leaf)")
    refute_equal source, bad
    functions, data, raw = Ze0::Machine.compile(bad, "gc.rb")
    out = StringIO.new
    assert_raises(Ze0::IR::Interp::Aborted) do
      Ze0::IR::Interp.new(functions, data: data, raw: raw, out: out, err: out).run(%w[gc stress])
    end
    assert_equal "a live object points at a freed cell\n", out.string
  end

  # An oracle that answers the same whatever the program does is no
  # oracle: break one constant and the interpreter must see it.
  def test_a_failing_fact_is_visible
    functions, data = Ze0::Native::Fixtures.build("arith")
    broken = functions.last.blocks.flat_map(&:insts).find { |i| i.args == [81_985_529_216_486_894] }
    refute_nil broken, "arith no longer names the constant this check breaks"
    broken.args[0] = 81_985_529_216_486_893
    status, = answers(functions, data, [], %w[arith])
    assert_equal 2, status, "the broken fact was not seen"
  end

  # A null dereference traps rather than reading whatever is at zero.
  def test_a_null_load_traps
    f = Ze0::IR::Function.new("main", %w[i32 i64], "i32")
    f.ret(f.ireduce("i32", f.fetch("i64", f.iconst("i64", 0))))
    e = assert_raises(Ze0::IR::Interp::Trapped) { answers([f], [], [], %w[null]) }
    assert_includes e.message, "outside the program's memory"
  end
end
