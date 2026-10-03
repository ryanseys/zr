# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/machine/host"

# The kernel on CRuby (`Machine::Host`, A7): the type model of A6, real
# memory, and the forms a kernel file declares with.
class MachineHostTest < Minitest::Test
  SOURCE = <<~RUBY
    module Zr::Kern
      Libc.import :strlen, [Ptr] => Word
      Pair = layout head: Word, tail: I32, flag: Bool
      Twice = fn [Word] => Word
      LIMIT = Pair.size * 2

      #: (word) -> word
      def twice(n)
        n + n
      end

      #: (ptr) -> word
      def through(fp)
        Twice.call(fp, 21)
      end

      #: (word) -> word
      def scratch(n)
        p = Machine.slot(16)
        Machine.store64(p, 8, n)
        Machine.load64(p, 8)
      end

      #: () -> word
      def length
        Libc.strlen(Machine.bytes("four"))
      end

      #: (ptr, word) -> word
      def pair(p, n)
        Pair.set_head(p, n)
        Pair.set_tail(p, Machine.i32(0 - 1))
        Pair.set_flag(p, true)
        Pair.head(p) + Machine.sword(Pair.tail(p))
      end
    end
  RUBY

  def host
    @host ||= Dir.mktmpdir("zr-host-") do |dir|
      path = File.join(dir, "k.rb")
      File.write(path, SOURCE)
      Zr::Machine::Host.new([path])
    end
  end

  def test_a_def_is_a_method_and_a_constant_folds
    assert_equal 14, host.call(:twice, 7)
    assert_equal 32, host.kern::LIMIT
  end

  def test_a_layout_reads_and_writes_memory
    p = Zr::Machine::Host::Memory.zeroed(host.kern::Pair.size)

    assert_equal 41, host.call(:pair, p, 42)
    assert_equal [0, 8, 12, 16], [*host.kern::Pair.layout_fields.values.map(&:first), host.kern::Pair.size]
    assert host.kern::Pair.flag(p)
  end

  def test_a_slot_is_given_back_when_its_def_returns
    top = host.slot_top

    assert_equal 9, host.call(:scratch, 9)
    assert_equal top, host.slot_top
  end

  def test_an_address_calls_the_def_from_ruby_and_from_c
    fp = host.addr("twice")

    assert_equal 42, host.call(:through, fp)
    assert_equal 42, Fiddle::Function.new(fp, [Fiddle::TYPE_LONG_LONG], Fiddle::TYPE_LONG_LONG).call(21)
  end

  def test_libc_calls_c
    assert_equal 4, host.call(:length)
  end

  def test_the_intrinsics_keep_the_type_model
    m = host.kern::Machine

    assert_equal [-1, 255, 0xFFFF_FFFF], [m.i32(0xFFFF_FFFF), m.u8(-1), m.u32(-1)]
    assert_equal [-3, -1, 3, 1], [m.sdiv(-7, 2), m.srem(-7, 2), m.sdiv(7, 2), m.srem(7, 2)]
    assert_equal [-(1 << 63), 0, (1 << 63)], [m.add_wrap((1 << 63) - 1, 1), m.uadd_wrap((1 << 64) - 1, 1), m.ushl_wrap(1, 63)]
    assert_equal [-1, (1 << 64) - 1], [m.word((1 << 64) - 1), m.ptr(-1)]
    assert_equal [1.5, 4_609_434_218_613_702_656], [m.f64(m.bits(1.5)), m.bits(1.5)]
    assert_equal [64, 0, 63, 2], [m.ctz(0), m.clz(-1), m.clz(1), m.popcnt(5)]
    assert_equal [-0.0, -1.0, 2.0], [m.ceil(-0.5), m.floor(-0.5), m.nearest(2.5)]
    assert_equal [(1 << 63) - 1, 0], [m.to_int(1e30), m.to_int(Float::NAN)]
  end

  # A def that can collect and loops keeps its Value locals as roots. A
  # local that a Value field of a layout gives is one of them.
  def test_a_value_read_from_a_field_is_a_root
    source = <<~RUBY
      module Zr::Kern
        Cell = layout klass: Value, count: Word
        collects :zr_gc

        #: () -> void
        def zr_gc
        end

        #: (ptr) -> word
        def walk(p)
          v = Cell.klass(p)
          n = Cell.count(p)
          while n > 0
            zr_gc
            n -= 1
          end
          0
        end
      end
    RUBY
    rooted = Dir.mktmpdir("zr-host-") do |dir|
      path = File.join(dir, "k.rb")
      File.write(path, source)
      Zr::Machine::Host.new([path]).instance_variable_get(:@rooted)
    end

    assert_equal [:v], rooted.fetch("walk")
  end

  # Each layout of the kernel has the offsets and size that the lowering
  # gives it.
  def test_each_kernel_layout_is_the_lowerings
    files = Zr::RuntimeSources.for(Zr::Target::AARCH64_DARWIN).kernel_files
    unit = Zr::Machine::Lower.new(files.map { |f| [File.read(f), f] }, Zr::Machine::Symbols.new).tap(&:run)
    kern = Zr::Machine::Host.new(files).kern

    names = unit.declared_structs
    assert_operator names.size, :>, 50
    names.each do |name|
      lowered = unit.struct_for(name)
      hosted = kern.const_get(name)

      assert_equal lowered.size, hosted.layout_size, name
      assert_equal lowered.fields.transform_values(&:first), hosted.layout_fields.transform_values(&:first), name
    end
  end
end
