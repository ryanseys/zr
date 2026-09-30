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

class B_to_f
  def to_f = 7
end

def p_to_f(v)
  v.to_f
end

p p_to_f(B_to_f.new)
p p_to_f("1.5")

