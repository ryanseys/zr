# Instance variables set with Array.new(n, FILL) hold the FILL value in
# each element: a Float, a Symbol or an object. The GC keeps the object
# elements alive.
#
# The Float values have a non-zero fractional part, so `puts` shows them
# as CRuby does.

class T_ivar_float_array_Box
  attr_accessor :nums
  def initialize
    @nums = Array.new(3, 0.5)
  end
end

class T_ivar_float_array_SymHolder
  attr_accessor :tags
  def initialize
    @tags = Array.new(2, :alpha)
  end
end

class T_ivar_float_array_Marker
  attr_accessor :id
  def initialize(id)
    @id = id
  end
end

class T_ivar_float_array_ObjHolder
  attr_accessor :marks
  def initialize
    @marks = Array.new(3, T_ivar_float_array_Marker.new(42))
  end
end

b = T_ivar_float_array_Box.new
puts b.nums[0]      # 0.5
puts b.nums[1]      # 0.5
puts b.nums[2]      # 0.5
puts b.nums.length  # 3

s = T_ivar_float_array_SymHolder.new
puts s.tags[0]      # alpha
puts s.tags[1]      # alpha
puts s.tags.length  # 2

m = T_ivar_float_array_ObjHolder.new
puts m.marks[0].id  # 42
puts m.marks[1].id  # 42  (Array.new(n, obj) shares the same obj)
puts m.marks[2].id  # 42
puts m.marks.length # 3
