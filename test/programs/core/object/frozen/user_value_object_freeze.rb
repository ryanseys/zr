# freeze on an instance of a small immutable class with only scalar ivars.
# freeze returns self, and the object stays usable. frozen? on a new object
# reads false, but it must still evaluate its receiver, so a side-effecting
# receiver expression is not discarded.
class Point
  attr_reader :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end
end

pt = Point.new(3, 4)
q = pt.freeze
puts q.x
puts q.y
puts pt.x

$calls = 0
def make_point
  $calls += 1
  Point.new(5, 6)
end

puts make_point.frozen?
puts $calls
