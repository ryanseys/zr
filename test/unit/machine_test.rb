# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/lower"
require_relative "../../lib/zr/native/build"

# Tests the kernel subset, compiled alone (without the zr runtime):
# - each `test/machine/<name>.rb` compiles to a binary that prints
#   `<name>.out`;
# - each `test/machine/units/<name>/` is one unit of several files that
#   prints its `out`;
# - each `test/machine/refused/` file is refused with the message its
#   first line gives.
class MachineTest < Minitest::Test
  Dir[File.join(ROOT, "test/machine/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      functions, data, raw = Zr::Machine.compile(File.read(rb), rb)
      Dir.mktmpdir("zr-machine-") do |dir|
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.binary(functions, data, bin, work: dir, raw: raw)
        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus, "#{name} exited #{$?.exitstatus}"
        assert_equal File.binread(rb.sub(/\.rb\z/, ".out")), out
      end
    end
  end

  Dir[File.join(ROOT, "test/machine/units/*/")].sort.each do |unit|
    name = File.basename(unit)
    define_method("test_unit_#{name}") do
      functions, data, raw = Zr::Machine.compile_unit(Dir[File.join(unit, "*.rb")].sort)
      Dir.mktmpdir("zr-machine-") do |dir|
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.binary(functions, data, bin, work: dir, raw: raw)
        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus, "#{name} exited #{$?.exitstatus}"
        assert_equal File.binread(File.join(unit, "out")), out
      end
    end
  end

  # Runs the collector under stress, with a collection at each
  # allocation. The output must not change. A program that removes a
  # root from its record must abort.
  def test_gc_under_stress
    source = File.read(File.join(ROOT, "test/machine/gc.rb"))
    bad = source.sub("      Machine.store64(rec, 24, leaf)\n      leaf = 0\n", "      Machine.store64(rec, 24, 0)\n")
                .sub("      Machine.store64(pair, 8, Machine.load64(rec, 24))", "      Machine.store64(pair, 8, leaf)")
    refute_equal source, bad
    Dir.mktmpdir("zr-machine-") do |dir|
      { "good" => source, "bad" => bad }.each do |name, text|
        functions, data, raw = Zr::Machine.compile(text, "gc.rb")
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.binary(functions, data, bin, work: dir, raw: raw)
        out = IO.popen([bin, "stress"], err: %i[child out], &:read)
        if name == "good"
          assert_equal File.binread(File.join(ROOT, "test/machine/gc.out")), out
        else
          assert_equal "a live object points at a freed cell\n", out
          assert_equal Signal.list["ABRT"], $?.termsig, "the missed root did not abort"
        end
      end
    end
  end

  # A small def that starts with a guard clause is inlined. `main` of
  # `guards.rb` calls each def, but after inlining it calls only the two
  # imports.
  def test_small_def_with_guard_clause_is_inlined
    rb = File.join(ROOT, "test/machine/guards.rb")
    functions, = Zr::Machine.compile(File.read(rb), rb)
    main = functions.find { |f| f.name == "main" }
    called = main.blocks.flat_map(&:insts).select { |i| i.op == :call }.map { |i| main.callees.find { |c| c.fn == i.callee }.symbol }.uniq.sort

    assert_equal %w[exit write], called
  end

  # A store of a Value into a cell runs the write barrier, unless the
  # cell is an image in a slot of the frame: such an image has FL_STACK,
  # so it is never old. A local that can also hold another address keeps
  # the barrier. Here the barrier calls `abort`, so its calls are visible.
  def test_a_stack_image_gets_no_write_barrier
    source = <<~RUBY
      module Zr::Kern
        module Libc
          #: () -> void
          def self.abort = Machine.import
        end

        class RBasic < Layout
          attr_accessor :flags #: word
          attr_accessor :klass #: value
        end

        class Cell < Layout
          attr_reader :basic #: RBasic
          attr_accessor :item #: value
        end

        #: (value, value) -> void
        def zr_write_barrier(owner, value)
          if owner == value
            Libc.abort()
          end
        end

        inline :zr_write_barrier

        #: (value, value) -> void
        def on_heap(cell, v)
          Cell[cell].item = v
        end

        #: (value) -> void
        def on_stack(v)
          d = Machine.slot(Cell.size)
          c = Machine.value(d)
          Cell[c].item = v
        end

        #: (value, value) -> void
        def either(cell, v)
          d = Machine.slot(Cell.size)
          c = Machine.value(d)
          if v == cell
            c = cell
          end
          Cell[c].item = v
        end
      end
    RUBY
    functions, = Zr::Machine.compile(source, "images.rb")
    aborts = functions.to_h do |f|
      calls = f.blocks.flat_map(&:insts).select { |i| i.op == :call }
      [f.name, calls.count { |i| f.callees.find { |c| c.fn == i.callee }.symbol == "abort" }]
    end

    assert_equal({ "on_heap" => 1, "on_stack" => 0, "either" => 1 }, aborts.slice("on_heap", "on_stack", "either"))
  end

  Dir[File.join(ROOT, "test/machine/refused/*.rb")].sort.each do |rb|
    define_method("test_refused_#{File.basename(rb, ".rb")}") do
      source = File.read(rb)
      want = source.lines.first.to_s[/\A# (.+)\n/, 1]
      refute_nil want, "#{rb}: no `# <expected refusal>` first line"
      e = assert_raises(Zr::Machine::Refused, "#{rb}: compiled, but must be refused") { Zr::Machine.compile(source, rb) }
      assert_includes e.message, want
    end
  end
end
