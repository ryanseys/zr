class Point
  attr_accessor :x, :y
  ORIGIN = 0
  def initialize(x, y)
    @x = x
    @y = y
  end
  def to_s
    "point"
  end
  def sum
    @x + @y
  end
end
module Shapes
  class Square
    def area(n)
      n * n
    end
  end
  SIDES = 4
end
pt = Point.new(1, 2)
p pt
puts pt, pt.sum, pt.x
pt.x = 10
p pt.x
p Point, Point.name, Point.superclass, Shapes::Square.new.area(3), Shapes::SIDES
p pt.class, pt.is_a?(Point), pt.is_a?(Object), 1.is_a?(Point), pt.respond_to?(:sum), pt.respond_to?(:nope)
p :sym, :"with space", "str\n\"q\"", nil, true, Point::ORIGIN
p pt == pt, pt != pt, pt.nil?, nil.nil?
class Point
  def double
    Point.new(@x * 2, @y * 2)
  end
end
p pt.double.sum
p Nope
