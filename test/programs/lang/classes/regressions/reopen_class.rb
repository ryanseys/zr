# Test: reopening a user-defined class adds to the existing class.

class T_reopen_class_Point
  attr_accessor :x
  def initialize(x, y)
    @x = x
    @y = y
  end
end

class T_reopen_class_Point
  attr_accessor :y
  def to_s
    "(" + @x.to_s + "," + @y.to_s + ")"
  end
end

p = T_reopen_class_Point.new(3, 4)
puts p.to_s
puts p.x
puts p.y
p.x = 10
p.y = 20
puts p.to_s

class T_reopen_class_Foo
end

class T_reopen_class_Foo
end

puts "ok"
