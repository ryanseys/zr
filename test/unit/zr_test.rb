# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/lower"
require_relative "../../lib/zr/native/build"

# The kernel dialect: each `test/zr/<name>.rb` compiles to a binary and
# prints `<name>.stdout`; each `test/zr/units/<name>/` is one unit of
# several files that prints its `stdout`; each
# `test/zr/refused/` fixture draws the refusal its first line names.
class ZrTest < Minitest::Test
  Dir[File.join(ROOT, "test/zr/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      functions, data, raw = Zr::Machine.compile(File.read(rb), rb)
      Dir.mktmpdir("zr-zr-") do |dir|
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.binary(functions, data, bin, work: dir, raw: raw)
        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus, "#{name} exited #{$?.exitstatus}"
        assert_equal File.binread(rb.sub(/\.rb\z/, ".stdout")), out
      end
    end
  end

  Dir[File.join(ROOT, "test/zr/units/*/")].sort.each do |unit|
    name = File.basename(unit)
    define_method("test_unit_#{name}") do
      functions, data, raw = Zr::Machine.compile_unit(Dir[File.join(unit, "*.rb")].sort)
      Dir.mktmpdir("zr-zr-") do |dir|
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.binary(functions, data, bin, work: dir, raw: raw)
        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus, "#{name} exited #{$?.exitstatus}"
        assert_equal File.binread(File.join(unit, "stdout")), out
      end
    end
  end

  # The collector under stress: the same answer with a collection at every
  # allocation, and a program that drops a root out of its record aborts.
  def test_gc_under_stress
    source = File.read(File.join(ROOT, "test/zr/gc.rb"))
    bad = source.sub("    Machine.store64(rec, 24, leaf)\n    leaf = 0\n", "    Machine.store64(rec, 24, 0)\n")
                .sub("    Machine.store64(pair, 8, Machine.load64(rec, 24))", "    Machine.store64(pair, 8, leaf)")
    refute_equal source, bad
    Dir.mktmpdir("zr-zr-") do |dir|
      { "good" => source, "bad" => bad }.each do |name, text|
        functions, data, raw = Zr::Machine.compile(text, "gc.rb")
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.binary(functions, data, bin, work: dir, raw: raw)
        out = IO.popen([bin, "stress"], err: %i[child out], &:read)
        if name == "good"
          assert_equal File.binread(File.join(ROOT, "test/zr/gc.stdout")), out
        else
          assert_equal "a live object points at a freed cell\n", out
          assert_equal Signal.list["ABRT"], $?.termsig, "the missed root did not abort"
        end
      end
    end
  end

  # A small def that opens with a guard clause is lowered in place: main
  # of `guards.rb` calls only the two imports, though it names every def.
  def test_a_guard_clause_does_not_keep_a_small_def_from_being_inlined
    rb = File.join(ROOT, "test/zr/guards.rb")
    functions, = Zr::Machine.compile(File.read(rb), rb)
    main = functions.find { |f| f.name == "main" }
    called = main.blocks.flat_map(&:insts).select { |i| i.op == :call }.map { |i| main.callees.find { |c| c.fn == i.callee }.symbol }.uniq.sort

    assert_equal %w[exit write], called
  end

  Dir[File.join(ROOT, "test/zr/refused/*.rb")].sort.each do |rb|
    define_method("test_refused_#{File.basename(rb, ".rb")}") do
      source = File.read(rb)
      want = source.lines.first.to_s[/\A# (.+)\n/, 1]
      refute_nil want, "#{rb}: no `# <expected refusal>` first line"
      e = assert_raises(Zr::Machine::Refused, "#{rb}: compiled, but must be refused") { Zr::Machine.compile(source, rb) }
      assert_includes e.message, want
    end
  end
end
