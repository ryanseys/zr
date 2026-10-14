# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../support/ir_interp"
require_relative "../../lib/zr/ir/passes"
require_relative "../../lib/zr/machine/lower"
require_relative "../native/fixtures"

# A second reference: `IR::Interp` runs each kernel subset program in
# place of a binary. The compiled binary and the interpreter compare with
# the same expected output. Thus a miscompile in
# `Backend::Aarch64::Codegen` shows as a difference between the two, not
# as a wrong result with no clue.
class InterpTest < Minitest::Test
  # Machine code has no IR to interpret. Thus the interpreter refuses a
  # program that calls machine code, with a message. `switch.rb` is the
  # only one.
  RAW = %w[switch].freeze

  # Runs each function through the passes of a build, with strict
  # checks, so the interpreter runs the output of the passes.
  def answers(functions, data, raw, argv)
    functions.each { |f| Zr::IR::Passes.prepare(f, strict: true) }
    out = StringIO.new
    status = Zr::IR::Interp.new(functions, data: data, raw: raw, out: out, err: out).run(argv)
    [status, out.string]
  end

  Zr::Native::Fixtures::NAMES.each do |name|
    define_method("test_native_#{name}") do
      functions, data = Zr::Native::Fixtures.build(name)
      status, out = answers(functions, data, [], [name])
      assert_equal 0, status, "#{name} exited #{status}"
      assert_equal File.binread(File.join(ROOT, "test/native/#{name}.out")), out
    end
  end

  Dir[File.join(ROOT, "test/machine/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_zr_#{name}") do
      functions, data, raw = Zr::Machine.compile(File.read(rb), rb)
      if RAW.include?(name)
        e = assert_raises(Zr::IR::Interp::Refused) { answers(functions, data, raw, [name]) }
        assert_includes e.message, "machine code, not IR"
      else
        status, out = answers(functions, data, raw, [name])
        assert_equal 0, status, "#{name} exited #{status}"
        assert_equal File.binread(rb.sub(/\.rb\z/, ".out")), out
      end
    end
  end

  Dir[File.join(ROOT, "test/machine/units/*/")].sort.each do |unit|
    name = File.basename(unit)
    define_method("test_zr_unit_#{name}") do
      compiled = Zr::Machine.unit(Dir[File.join(unit, "*.rb")].sort)
      functions, data, raw = compiled.functions, compiled.data, compiled.raw
      status, out = answers(functions, data, raw, [name])
      assert_equal 0, status, "#{name} exited #{status}"
      assert_equal File.binread(File.join(unit, "out")), out
    end
  end

  # Runs the collector under stress, as the compiled binary also does. A
  # program that removes a root from its record must abort.
  def test_a_missed_root_aborts
    source = File.read(File.join(ROOT, "test/machine/gc.rb"))
    bad = source.sub("      Machine.store64(rec, 24, leaf)\n      leaf = 0\n", "      Machine.store64(rec, 24, 0)\n")
                .sub("      Machine.store64(pair, 8, Machine.load64(rec, 24))", "      Machine.store64(pair, 8, leaf)")
    refute_equal source, bad
    functions, data, raw = Zr::Machine.compile(bad, "gc.rb")
    out = StringIO.new
    assert_raises(Zr::IR::Interp::Aborted) do
      Zr::IR::Interp.new(functions, data: data, raw: raw, out: out, err: out).run(%w[gc stress])
    end
    assert_equal "a live object points at a freed cell\n", out.string
  end

  # A reference that gives the same result for any program is useless.
  # Thus the test breaks one constant, and the interpreter must see it.
  def test_a_failing_fact_is_visible
    functions, data = Zr::Native::Fixtures.build("arith")
    broken = functions.last.blocks.flat_map(&:insts).find { |i| i.args == [81_985_529_216_486_894] }
    refute_nil broken, "arith no longer names the constant this check breaks"
    broken.args[0] = 81_985_529_216_486_893
    status, = answers(functions, data, [], %w[arith])
    # The constant fact is the fourth from the end: three facts follow it.
    assert_equal 8, status, "the broken fact was not seen"
  end

  # A null dereference traps. It does not read the memory at address 0.
  def test_a_null_load_traps
    f = Zr::IR::Function.new("main", %w[i32 i64], "i32")
    f.ret(f.ireduce("i32", f.fetch("i64", f.iconst("i64", 0))))
    e = assert_raises(Zr::IR::Interp::Trapped) { answers([f], [], [], %w[null]) }
    assert_includes e.message, "outside the program's memory"
  end
end
