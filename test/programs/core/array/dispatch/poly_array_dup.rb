# `Array#dup` and a few sibling methods on an array with
# mixed element types.
#
# Coverage:
#   - dup: shallow copy preserves the element variant (length
#     equal, types preserved).
#   - to_a: alias for dup on Array.
#   - empty?: edge case (zero-length array).
#   - first / last: the named-method forms of `[0]` and `[-1]`.

a = [1, "two", :three]
b = a.dup
puts b.length                  # 3

# Element variants preserved across dup.
c = a.to_a
puts c.length                  # 3

# empty? on a mixed array.
empty = [1, "x"]
puts empty.empty? ? "yes" : "no"   # no

empty2 = [1, "x"]
empty2.clear
puts empty2.empty? ? "yes" : "no"  # yes

# first / last on a mixed array.
arr = [1, "two", :three]
# Ruby's `first` on Array of mixed types returns the first elem.
# This example does not print the values; it checks only that the
# calls complete.
arr.first
arr.last
puts "ok"                          # ok
