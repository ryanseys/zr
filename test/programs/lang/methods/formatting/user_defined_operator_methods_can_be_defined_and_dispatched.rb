# A user class can define a method whose name is an operator (`+`, `<=>`,
# `[]`, ...), and a call with that operator goes to it. The Integer and
# Float operators do not test the defining side, so this example does.

class Vector
  attr_reader :x, :y
  def initialize(x, y)
    @x = x
    @y = y
  end
  def +(other)
    Vector.new(@x + other.x, @y + other.y)
  end
  def <=>(other)
    (@x * @x + @y * @y) <=> (other.x * other.x + other.y * other.y)
  end
  def to_s
    "(#{@x}, #{@y})"
  end
end
v1 = Vector.new(1, 2)
v2 = Vector.new(3, 4)
v3 = v1 + v2
puts v3.to_s
puts(v1 <=> v2)
puts(v2 <=> v1)
puts(v1 <=> v1)
