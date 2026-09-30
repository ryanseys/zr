# `[String.new]` (and `[s]` where `s = String.new`) is an Array of
# mutable Strings. length / push / pop / [] work on it.
#
# `["", String.new]` mixes a string literal and a mutable String.
# Both elements are in the Array.

arr = [String.new]
puts arr.length

s = String.new
arr2 = [s]
puts arr2.length

# Mixed: literal + String.new. Both elements show up.
mixed = ["", String.new]
puts mixed.length
