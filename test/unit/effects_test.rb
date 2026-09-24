# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/lower"

# Tests what a kernel def can write (`IR::Effects`), as `Machine::Lower`
# computes it for a small unit:
# - A def writes the region of each store, and the regions of the defs
#   that it calls.
# - An import or a call through a pointer writes everything.
# - A def that only returns the address of a static (every caller inlines
#   it) does not make a store through a pointer a write to that word.
class EffectsTest < Minitest::Test
  SOURCE = <<~'RB'
    Machine.import "write", [I32, Ptr, Word] => Word
    Machine.struct :Cell, basic: RBasic, next: Value
    Machine.struct :RBasic, flags: Word, klass: Value
    Machine.struct :Row, id: Word, value: Value
    Machine.sig :thunk, [] => Void

    sig [] => Ptr
    machine def gates
      Machine.static(:gates, 8)
    end

    sig [Word] => Void
    machine def set_gates(v)
      Machine.store64(gates(), 0, v)
    end

    sig [Word] => Void
    machine def set_slowly(v)
      set_gates(v)
    end

    sig [Ptr, Value] => Void
    machine def link(cell, v)
      Cell.set_next(cell, v)
    end

    sig [Ptr, Word] => Void
    machine def fill(row, v)
      Row.set_id(row, v)
    end

    sig [Ptr] => Void
    machine def poke(p)
      Machine.store64(p, 0, 1)
    end

    sig [Ptr] => Void
    machine def tell(p)
      write(1, p, 1)
    end

    sig [Ptr] => Void
    machine def jump(fn)
      Machine.call(:thunk, fn)
    end

    sig [] => Word
    machine def pure
      3
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

# Tests the effects of kernel defs in the recorded darwin description.
# Allocation can run the collector, which changes the method stamps when
# it frees a class. Allocation never writes the gate word. A send can
# write anything.
class KernelEffectsTest < Minitest::Test
  def kernel
    text = File.read(File.join(ROOT, "runtime/ext/os/darwin/zr_description.rb"))[/<<~ROWS\n(.*?)^\s*ROWS$/m, 1].gsub(/^ +/, "")
    Zr::Machine::Description.parse(text)
  end

  def test_allocation_writes_stamps_and_not_gates
    alloc = kernel.def_for("zr_alloc").effects
    assert Zr::IR::Effects.writes?(alloc, :stamps)
    refute Zr::IR::Effects.writes?(alloc, :gates)
    assert_equal Zr::IR::Effects::ALL, kernel.def_for("zr_send_cached").effects
    assert Zr::IR::Effects.writes?(kernel.def_for("zr_gates_recheck").effects, :gates)
  end
end
