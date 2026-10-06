# A unary operator method, `def -@` or `def +@`, answers `-obj` or
# `+obj`. Gems such as latinum and as-duration negate a value this way.
class Money
  attr_reader :cents
  def initialize(c)
    @cents = c
  end
  def -@
    Money.new(-@cents)
  end
  def +@
    Money.new(@cents)
  end
end

puts((-Money.new(5)).cents)
puts((+Money.new(7)).cents)
puts((-(-Money.new(9))).cents)
