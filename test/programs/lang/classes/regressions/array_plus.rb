# Array#+ joins two mixed Arrays, and two Arrays of user objects.

# mixed element classes
a = [1, "x"]
b = [2, "y"]
puts (a + b).length

# user objects
class T_array_plus_Bar
  def initialize(x); @x = x; end
  attr_accessor :x
end

c = [T_array_plus_Bar.new(1)]
d = [T_array_plus_Bar.new(2)]
puts (c + d).length
