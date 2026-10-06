# `def m = (@x = 2; self)` -- a method body that is a parenthesized
# sequence ending in `self` returns the object itself, not a copy.

class C
  def initialize = (@x = 1)
  def tap_self = (@x = 2; self)
  attr_reader :x
end
c = C.new
p c.tap_self.equal?(c)
p c.x
