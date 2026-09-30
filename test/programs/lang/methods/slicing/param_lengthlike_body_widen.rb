# Body-usage param inference widens an int/nil-defaulted param
# to "any type" when the body calls a length-like method
# (length / size / empty?) on the param. These methods exist
# on String / Array / Hash but NOT on Integer, so such a call
# shows the param is one of those container types. The call
# then works for a String, every Array kind and every Hash kind.
#
# The rows cover String, Array and Hash (the Hash row prints 2).
#
# nil semantics: nil has no #length, so the call raises
# NoMethodError, as CRuby does. The test asserts the nil case
# through a rescue.
#
# Conservative classifier: only length / size / empty? widen.
# These don't exist on Integer, so the widening is sound.
# Methods that DO exist on Integer (<<, &, |, +, -, *, [])
# are deliberately excluded -- a body like
# `def poke(data); data << 8; end` (optcarrot's PPU) is
# legitimately Integer arithmetic and would break under a
# broader widening.

def consume_length(x)
  x.length
end

def consume_empty(x)
  x.empty?
end

class Box
  attr_accessor :contents
end

b = Box.new
begin
  puts consume_length(b.contents)
rescue NoMethodError => e
  puts e.message
end
b.contents = "hello"
puts consume_length(b.contents)
b.contents = [1, 2, 3, 4]
puts consume_length(b.contents)
b.contents = { "a" => 1, "b" => 2 }
puts consume_length(b.contents)
puts consume_empty(b.contents)
b.contents = {}
puts consume_empty(b.contents)
