# Pointer-array (`<obj>_ptr_array`) coverage — typed-obj `[]` map,
# value-class instances in array literals (and via `push`/`<<`),
# and slot widening from `[nil] * N` writes. Was four tests; the
# only class-name collisions were Foo (same definition reused
# across the two value-class sections — kept once) and Bag (two
# unrelated shapes — section 1's Bag renamed to MapBag).


# A class with no attr_writers / no mutating methods would normally
# be value-type'd, but its instances landing in an array literal or
# being push'd into one must demote it to a heap-allocated obj so
# `sp_PtrArray_push`'s `void *` arg type-checks. PR #87 covered the
# literal case; #91 (follow-up) extended it to push / <<.
class Foo
  def initialize(x); @x = x; end
  attr_reader :x
end

# Literal form.
flit = [Foo.new(1), Foo.new(2), Foo.new(3)]
puts flit.length
flit.each { |f| puts f.x }

# `push` form.
fpush = []
fpush.push(Foo.new(1))
fpush.push(Foo.new(2))
puts fpush.length
fpush.each { |f| puts f.x }

# `<<` form (same code path through the parser).
fsh = []
fsh << Foo.new(10)
fsh << Foo.new(20)
fsh << Foo.new(30)
puts fsh.length
fsh.each { |f| puts f.x }
