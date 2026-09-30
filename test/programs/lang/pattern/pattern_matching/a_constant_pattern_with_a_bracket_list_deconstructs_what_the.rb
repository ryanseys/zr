class Point
  def initialize(x, y)
    @x = x
    @y = y
  end
  def deconstruct
    [@x, @y]
  end
  def deconstruct_keys(keys)
    { x: @x, y: @y }
  end
end

p1 = Point.new(1, 2)
case p1
in [px, py]
  puts "array: #{px}, #{py}"
end
case p1
in Point(x:, y:)
  puts "constant: #{x}, #{y}"
end

