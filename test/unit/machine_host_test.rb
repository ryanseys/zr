# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/machine/host"

# The kernel on CRuby (`Machine::Host`): the kernel's type model, real
# memory, and the forms a kernel file declares with.
class MachineHostTest < Minitest::Test
  SOURCE = <<~RUBY
    module Zr::Kern
      module Libc
        #: (ptr) -> word
        def self.strlen(p) = Machine.import
      end

      class Pair < Layout
        attr_accessor :head #: word
        attr_accessor :tail #: i32
        attr_accessor :flag #: bool
      end

      module Twice
        #: (ptr, word) -> word
        def self.call(fn, n) = Machine.indirect
      end

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
        Pair[p].head = n
        Pair[p].tail = Machine.i32(0 - 1)
        Pair[p].flag = true
        Pair[p].head + Machine.sword(Pair[p].tail)
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
    assert_equal 16, host.kern::Pair.size
    pair = host.kern::Pair[p]
    assert_equal [42, -1, true], [pair.head, pair.tail, pair.flag]
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
        class Cell < Layout
          attr_accessor :klass #: value
          attr_accessor :count #: word
        end

        collects :zr_gc

        #: () -> void
        def zr_gc
        end

        #: (ptr) -> word
        def walk(p)
          v = Cell[p].klass
          n = Cell[p].count
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

  # A call through a signature can collect, as in the lowering
  # (`Lower#collecting_defs`), so a def that makes one in a loop keeps its
  # Value locals as roots.
  def test_a_call_through_a_signature_can_collect
    source = <<~RUBY
      module Zr::Kern
        module Step
          #: (ptr) -> void
          def self.call(fn) = Machine.indirect
        end

        #: (ptr, ptr) -> word
        def walk(p, fn)
          v = Machine.value(Machine.load64(p, 0))
          n = Machine.load64(p, 8)
          while n > 0
            Step.call(fn)
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

  # Each layout class of the kernel has the lowering's size, a reader for
  # each field, and a writer for each field that is not an embedded
  # layout.
  def test_each_kernel_layout_is_the_lowerings
    files = Zr::RuntimeSources.for(Zr::Target::AARCH64_DARWIN).kernel_files
    unit = Zr::Machine::Lower.new(files.map { |f| [File.read(f), f] }, Zr::Machine::Symbols.new).tap(&:run)
    kern = Zr::Machine::Host.new(files).kern

    names = unit.declared_structs
    assert_operator names.size, :>, 50
    names.each do |name|
      lowered = unit.struct_for(name)
      hosted = kern.const_get(name)

      assert_equal lowered.size, hosted.size, name
      lowered.fields.each do |field, (_, type)|
        assert hosted.method_defined?(field), "#{name}##{field}"
        assert_equal !unit.struct_for(type), hosted.method_defined?(:"#{field}="), "#{name}##{field}="
      end
    end
  end

  # A program of test/machine prints on CRuby what its binary prints
  # (test/unit/machine_test.rb), and exits 0: the kernel subset means the
  # same on both. switch.rb calls the raw zr_switch, which only a binary
  # has.
  RUN = <<~RUBY.freeze
    require #{File.join(ROOT, "lib/zr/machine/host").dump}
    Zr::Machine::Host.new([ARGV[0]]).call(:main, 0, 0)
  RUBY

  (Dir[File.join(ROOT, "test/machine/*.rb")].sort - [File.join(ROOT, "test/machine/switch.rb")]).each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}_prints_on_the_host_what_its_binary_prints") do
      out, status = Open3.capture2(Gem.ruby, "-e", RUN, rb)

      assert_equal 0, status.exitstatus, "#{name} exited #{status.exitstatus}"
      assert_equal File.binread(rb.sub(/\.rb\z/, ".out")), out
    end
  end
end
