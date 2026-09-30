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

# the reproduction: a method that answers an object of its own class, reached
# through a widened receiver, with the receiver's own arm running (@asked is 1)
class Chain
  def initialize(text)
    @text = text
    @asked = 0
  end

  attr_reader :asked

  def to_s = @text

  def join(*parts)
    @asked += 1
    parts.reduce(self) { |acc, part| Chain.new("#{acc}/#{part}") }
  end
end

def joined(value)
  value.join("b")
end

chain = Chain.new("/tmp")
p "#{joined(chain)}"
p chain.asked
p joined(["x", "y"])

