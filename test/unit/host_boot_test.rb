# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/host/boot"

# The whole kernel booted on CRuby (`Machine::Host::Boot`, A7): the heap,
# the core classes, and a collection that keeps each Value a host def
# holds.
class HostBootTest < Minitest::Test
  def self.boot = @boot ||= Zr::Machine::Host::Boot.new

  def setup
    @boot = self.class.boot
    @k = @boot.kern
    @host = @boot.host
  end

  def string(text)
    @k.zr_str_new(@host.bytes(text), text.bytesize)
  end

  def text(s) = Zr::Machine::Host::Memory.read(@k::RString[s].ptr, @k::RString[s].len)

  # zr_cframe_call saves its context after a C frame record's fields.
  def test_a_c_frame_record_has_the_size_that_the_stub_steps_over
    require_relative "../../lib/zr/backend/aarch64/stub"
    assert_equal Zr::Backend::Aarch64::Stub::CFRAME_CONTEXT, @k::CFrame.size
    assert_equal @k::CFrame.size + @k::CONTEXT_BYTES, @k::CFRAME_BYTES
  end

  # A C call in a C frame record gives C's result, and leaves no record
  # linked in the task.
  def test_a_c_call_returns_what_c_returns
    labs = Fiddle::Handle::DEFAULT["labs"]
    argv = Zr::Machine::Host::Memory.zeroed(64)
    Zr::Machine::Host::Memory.write(argv, [-42].pack("q<"))

    assert_equal 42, @k.zr_call_c(labs, argv, 1)
    assert_equal 0, @k::Task[@k.zr_task].cframe
  end

  def test_the_boot_makes_the_core_classes
    object = @k.zr_global(@k::G_OBJECT)

    assert_equal @k.zr_global(@k::G_NUMERIC), @k::RClass[@k.zr_global(@k::G_INTEGER)].superclass
    assert_equal "Object", text(@k.zr_class_path(object))
  end

  def test_a_hash_and_an_array_hold_their_values
    hash = @host.pin(@k.zr_hash_new)
    50.times { |i| @k.zr_hash_store(hash, @k.zr_fix(i), string("v#{i}")) }

    assert_equal "v7", text(@k.zr_hash_lookup(hash, @k.zr_fix(7)))
  end

  # Under stress each allocation collects, and a freed cell is poisoned.
  # A Value that a host def held and did not pin would be freed.
  def test_a_collection_at_each_allocation_keeps_every_held_value
    @k.zr_gc_set_stress(@k::QTRUE)
    ary = @host.pin(@k.zr_ary_new(0))
    before = @k::Heap[@k.zr_heap].collections
    100.times do |i|
      s = string("left #{i} ")
      @k.zr_str_cat_bytes(s, string("right"))
      @k.zr_ary_push(ary, s)
    end

    assert_operator @k::Heap[@k.zr_heap].collections - before, :>=, 100
    entries = (0...100).map { |i| text(@k::Machine.load64(@k::RArray[ary].ptr, i * 8)) }

    assert_equal (0...100).map { |i| "left #{i} right" }, entries
  ensure
    @k.zr_gc_set_stress(@k::QFALSE)
  end
end
