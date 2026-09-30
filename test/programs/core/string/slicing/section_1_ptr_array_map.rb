# Pointer-array (`<obj>_ptr_array`) coverage — typed-obj `[]` map,
# value-class instances in array literals (and via `push`/`<<`),
# and slot widening from `[nil] * N` writes. Was four tests; the
# only class-name collisions were Foo (same definition reused
# across the two value-class sections — kept once) and Bag (two
# unrelated shapes — section 1's Bag renamed to MapBag).


# `.map { ... }` on an ivar or local that holds an array of Box objects.
class Box
  attr_reader :v
  def initialize(v); @v = v; end
end

class MapBag
  def initialize
    @items = [Box.new(1), Box.new(2), Box.new(3)]
  end
  def doubled
    @items.map { |b| b.v * 2 }
  end
  def names
    @items.map { |b| "v=#{b.v}" }
  end
end

mbag = MapBag.new
mints = mbag.doubled
puts mints.length    # 3
puts mints[0]        # 2
puts mints[2]        # 6
mnames = mbag.names
puts mnames.length   # 3
puts mnames[0]       # v=1
puts mnames[2]       # v=3
