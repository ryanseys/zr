# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../../lib/zr/machine/lower"
require "zr/runtime"

# Tests what a kernel def can write (`IR::Effects`), as `Machine::Lower`
# computes it for a small unit:
# - A def writes the region of each store, and the regions of the defs
#   that it calls.
# - An import or a call through a pointer writes everything.
# - A def that only returns the address of a static (every caller inlines
#   it) does not make a store through a pointer a write to that word.
class EffectsTest < Minitest::Test
  SOURCE = <<~'RB'
    module Zr::Kern
      module Libc
        #: (i32, ptr, word) -> word
        def self.write(i, p, n) = Machine.import
      end

      class Cell < Layout
        attr_reader :basic #: RBasic
        attr_accessor :next #: value
      end

      class RBasic < Layout
        attr_accessor :flags #: word
        attr_accessor :klass #: value
      end

      class Row < Layout
        attr_accessor :id #: word
        attr_accessor :value #: value
      end

      module Thunk
        #: (ptr) -> void
        def self.call(fn) = Machine.indirect
      end

      #: () -> ptr
      def gates
        Machine.static(:gates, 8)
      end

      #: (word) -> void
      def set_gates(v)
        Machine.store64(gates(), 0, v)
      end

      #: (word) -> void
      def set_slowly(v)
        set_gates(v)
      end

      #: (ptr, value) -> void
      def link(cell, v)
        Cell[cell].next = v
      end

      #: (ptr, word) -> void
      def fill(row, v)
        Row[row].id = v
      end

      #: (ptr) -> void
      def poke(p)
        Machine.store64(p, 0, 1)
      end

      #: (ptr) -> void
      def tell(p)
        Libc.write(1, p, 1)
      end

      #: (ptr) -> void
      def jump(fn)
        Thunk.call(fn)
      end

      #: () -> word
      def pure
        3
      end

      # Takes the address of a def that writes the gates, and calls
      # nothing.
      #: (ptr) -> word
      def names_set_gates(fn)
        if fn == Machine.addr(:set_gates)
          1
        else
          0
        end
      end

      # Calls that def through its address.
      #: () -> void
      def runs_set_gates
        Thunk.call(Machine.addr(:set_gates))
      end
    end
  RB

  def effects
    @effects ||= begin
      unit = Zr::Machine::Lower.new([[SOURCE, "effects_test.rb"]])
      unit.run
      unit.declared_defs.transform_values(&:effects)
    end
  end

  def bit(region) = Zr::IR::Effects.bit(region)

  def test_static_store_writes_its_region_through_calls
    assert_equal bit(:gates), effects.fetch("set_gates")
    assert_equal bit(:gates), effects.fetch("set_slowly"), "through a call"
    assert_equal 0, effects.fetch("pure")
    assert_equal 0, effects.fetch("gates"), "answering the address writes nothing"
  end

  def test_a_field_store_is_a_write_to_the_heap_or_a_payload
    assert_equal bit(:heap), effects.fetch("link")
    assert_equal bit(:malloc), effects.fetch("fill")
  end

  def test_pointer_store_writes_unknown_region
    assert_equal Zr::IR::Effects::UNKNOWN, effects.fetch("poke")
  end

  # A def whose address a body takes is not called there. A call through
  # the address is a call through a pointer, which writes everything.
  def test_taking_an_address_is_not_a_call
    assert_equal 0, effects.fetch("names_set_gates")
    assert_equal Zr::IR::Effects::ALL, effects.fetch("runs_set_gates")
  end

  def test_import_writes_unknown_and_indirect_call_writes_all
    assert_equal Zr::IR::Effects::UNKNOWN, effects.fetch("tell")
    assert_equal Zr::IR::Effects::ALL, effects.fetch("jump")
    assert_equal Zr::IR::Effects::ALL, Zr::IR::Effects.import("pthread_create")
    assert_equal Zr::IR::Effects::ALL, Zr::IR::Effects.import("zr_toplevel")
  end

  def test_description_includes_effects
    unit = Zr::Machine::Lower.new([[SOURCE, "effects_test.rb"]])
    unit.run
    text = Zr::Machine::Description.of(unit).to_text
    assert_includes text, "e set_gates #{bit(:gates)}\n"
    assert_equal bit(:gates), Zr::Machine::Description.parse(text).def_for("set_slowly").effects
  end
end

# Tests the effects of kernel defs in the darwin kernel's description.
# Allocation can run the collector, which changes the method stamps when
# it frees a class. Allocation never writes the gate word. A send can
# write anything.
class KernelEffectsTest < Minitest::Test
  # Lowered once for the class: the kernel takes seconds to lower.
  def self.kernel = @kernel ||= Zr::Machine::Description.of(Zr::Runtime.new(Zr::Target.fetch("aarch64-apple-darwin")).unit)

  def kernel = self.class.kernel

  def test_allocation_writes_stamps_and_not_gates
    alloc = kernel.def_for("zr_alloc").effects
    assert Zr::IR::Effects.writes?(alloc, :stamps)
    refute Zr::IR::Effects.writes?(alloc, :gates)
    assert_equal Zr::IR::Effects::ALL, kernel.def_for("zr_send_cached").effects
    assert Zr::IR::Effects.writes?(kernel.def_for("zr_gates_recheck").effects, :gates)
  end
end
