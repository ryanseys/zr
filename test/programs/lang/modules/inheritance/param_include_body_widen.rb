# `.include?` is an "ambiguous receiver" method: it exists on
# String / Array / Hash / Range but NOT on Integer. Thus
# `cols.include?(:updated_at)` on an int/nil-defaulted param
# widens the param to "any type".
#
# The call works for each Array and Hash kind (Hash#include?
# aliases has_key?), and for a String receiver it does a
# substring search, per CRuby's String#include? semantics.

def consume(coll)
  coll.include?(:x)
end

class Box
  attr_accessor :v
end

b = Box.new
puts consume(b.v)
b.v = [:y, :x, :z]
puts consume(b.v)
b.v = [:a, :b]
puts consume(b.v)
b.v = {x: 1, y: 2}
puts consume(b.v)
b.v = "abc"
puts consume(b.v)
