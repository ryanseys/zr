# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/lower"

# What a kernel def may write (`IR::Effects`), as `Machine::Lower`
# computes it over a small unit: the region of each store, closed over
# the defs called; an import or a call through a pointer writes
# everything; a def that only answers a static's address, which every
# caller inlines, does not make a store through a pointer a write to
# the word.
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

  def test_a_store_to_a_static_is_a_write_to_its_region_closed_over_the_calls
    assert_equal bit(:gates), effects.fetch("set_gates")
    assert_equal bit(:gates), effects.fetch("set_slowly"), "through a call"
    assert_equal 0, effects.fetch("pure")
    assert_equal 0, effects.fetch("gates"), "answering the address writes nothing"
  end

  def test_a_field_store_is_a_write_to_the_heap_or_a_payload
    assert_equal bit(:heap), effects.fetch("link")
    assert_equal bit(:malloc), effects.fetch("fill")
  end

  def test_a_store_through_a_pointer_writes_what_a_pointer_can_reach_and_no_guard_word
    assert_equal Zr::IR::Effects::UNKNOWN, effects.fetch("poke")
  end

  def test_an_import_writes_what_a_pointer_reaches_and_a_call_through_a_pointer_everything
    assert_equal Zr::IR::Effects::UNKNOWN, effects.fetch("tell")
    assert_equal Zr::IR::Effects::ALL, effects.fetch("jump")
    assert_equal Zr::IR::Effects::ALL, Zr::IR::Effects.import("pthread_create")
    assert_equal Zr::IR::Effects::ALL, Zr::IR::Effects.import("zr_toplevel")
  end

  def test_the_description_carries_the_effects
    unit = Zr::Machine::Lower.new([[SOURCE, "effects_test.rb"]])
    unit.run
    text = Zr::Machine::Description.of(unit).to_text
    assert_includes text, "e set_gates #{bit(:gates)}\n"
    assert_equal bit(:gates), Zr::Machine::Description.parse(text).def_for("set_slowly").effects
  end
end

# The kernel's own answers, as the blessed darwin description carries
# them: allocation may run the collector, which moves the stamps when
# it frees a class, and never touches the gate word; a send may do
# anything.
class KernelEffectsTest < Minitest::Test
  def kernel
    text = File.read(File.join(ROOT, "rt/ext/os/darwin/zr_description.rb"))[/<<~ROWS\n(.*?)^\s*ROWS$/m, 1].gsub(/^ +/, "")
    Zr::Machine::Description.parse(text)
  end

  def test_allocation_moves_the_stamps_and_leaves_the_gates_alone
    alloc = kernel.def_for("zr_alloc").effects
    assert Zr::IR::Effects.writes?(alloc, :stamps)
    refute Zr::IR::Effects.writes?(alloc, :gates)
    assert_equal Zr::IR::Effects::ALL, kernel.def_for("zr_send_cached").effects
    assert Zr::IR::Effects.writes?(kernel.def_for("zr_gates_recheck").effects, :gates)
  end
end
