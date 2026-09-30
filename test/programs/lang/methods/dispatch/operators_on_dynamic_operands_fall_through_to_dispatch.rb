# Operators on operands that are not Int/Float fall through to dynamic
# dispatch: String#+, and a user class's own operator method chained
# through an intermediate value of unknown type (`a << 1` returns
# self; the second `<<` dispatches dynamically).

module Cat
  def self.concat2(a, b)
    a + b
  end
end
puts Cat.concat2("foo", "bar")
class Acc
  def initialize
    @items = []
  end
  def <<(item)
    @items << item
    self
  end
  def size
    @items.length
  end
end
a = Acc.new
a << 1 << 2 << 3
puts a.size
