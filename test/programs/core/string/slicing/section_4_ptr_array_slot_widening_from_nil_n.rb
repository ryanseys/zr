# Pointer-array (`<obj>_ptr_array`) coverage — typed-obj `[]` map,
# value-class instances in array literals (and via `push`/`<<`),
# and slot widening from `[nil] * N` writes. Was four tests; the
# only class-name collisions were Foo (same definition reused
# across the two value-class sections — kept once) and Bag (two
# unrelated shapes — section 1's Bag renamed to MapBag).


# `@arr = [nil] * N` followed by `@arr[i] = obj` widens the slot
# to `<obj>_ptr_array`. Without the widening, the slot stays at
# the default IntArray and the object pointer write is truncated.
class Item
  def initialize(label)
    @label = label
    @history = [0]   # array ivar keeps Item off the value-type fast path
  end
  def visit
    @history << @history.last + 1
    @label
  end
  def visits
    @history.length - 1
  end
end

class Bag
  def initialize
    @slots = [nil] * 4
    @slots[0] = Item.new("a")
    @slots[1] = Item.new("b")
    @slots[3] = Item.new("d")
  end
  attr_reader :slots
  def visit_at(i)
    @slots[i].visit
  end
end

b = Bag.new
puts b.visit_at(0)
puts b.visit_at(1)
puts b.visit_at(3)
puts b.slots[0].visits   # 1
puts b.slots[1].visits   # 1
puts b.slots[3].visits   # 1
