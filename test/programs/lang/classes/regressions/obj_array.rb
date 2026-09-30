class T_obj_array_Point
  attr_accessor :x
  attr_accessor :y
  def initialize(x, y)
    @tag = "p"
    @x = x
    @y = y
  end
  def to_s
    x.to_s + "," + y.to_s
  end
end

points = [T_obj_array_Point.new(1, 2), T_obj_array_Point.new(3, 4), T_obj_array_Point.new(5, 6)]
points.each { |p|
  puts p.to_s
}
puts points.length

# push to obj array
more = []
more.push(T_obj_array_Point.new(10, 20))
more.push(T_obj_array_Point.new(30, 40))
more.each { |p|
  puts p.x + p.y
}
