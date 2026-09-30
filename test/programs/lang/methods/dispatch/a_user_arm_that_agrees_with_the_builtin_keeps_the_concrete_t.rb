# A call on a receiver of more than one class can reach a user method AND a
# builtin one, so the call's result must hold what either one returns:
# `Chain#join` answering a Chain gives the Chain, `def to_i = "seven"` gives
# the String, and `def empty? = 0` gives 0 -- 0 is truthy in Ruby.
#
# A user method whose return agrees with the builtin keeps the concrete type.
# This program walks the names one by one.

class B_join
  def join(*p) = "seven"
end

def p_join(v)
  v.join("b")
end

# a user arm that AGREES keeps the concrete type: this is what must not widen,
# or every poly.size boxes a count the whole program reads as a number
class Counted
  def size = 3
  def length = 4
end

def sized(v) = v.size
def lengthed(v) = v.length
p sized(Counted.new)
p sized([1, 2])
p lengthed(Counted.new)
p lengthed("abcde")
