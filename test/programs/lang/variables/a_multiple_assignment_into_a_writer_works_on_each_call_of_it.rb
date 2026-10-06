class Point
  attr_accessor :x
end
def set(o)
  o.x, rest = 7, 2
  o.x
end
p set(Point.new), set(Point.new)
