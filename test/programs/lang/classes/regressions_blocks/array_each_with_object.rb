# Array#each_with_object runs the block for each element, on a mixed
# Array and on an Array of user objects.

# mixed element classes
n = 0
[1, "x"].each_with_object("") {|_e, _a| n += 1 }
puts n

# user objects
class T_array_each_with_object_Bar
  def initialize(x); @x = x; end
  attr_accessor :x
end

m = 0
[T_array_each_with_object_Bar.new(1), T_array_each_with_object_Bar.new(2)].each_with_object("") {|_e, _a| m += 1 }
puts m
