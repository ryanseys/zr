# `a, b = self.method(...)` where `method` returns an Array of objects,
# Floats or Strings. Each shape below destructures into two locals,
# and each local gets its element.

class T_multi_write_typed_array_dispatch_Mat
  attr_accessor :v
  def initialize(v); @v = v; end
end

class T_multi_write_typed_array_dispatch_N
  def two_mats
    [T_multi_write_typed_array_dispatch_Mat.new(11), T_multi_write_typed_array_dispatch_Mat.new(22)]
  end
  def two_floats
    [1.5, 2.5]
  end
  def two_strs
    ["a", "b"]
  end

  def go_mats
    a, b = self.two_mats
    a.v + b.v
  end
  def go_floats
    a, b = self.two_floats
    a + b
  end
  def go_strs
    a, b = self.two_strs
    a + b
  end
end

n = T_multi_write_typed_array_dispatch_N.new
puts n.go_mats     # 33
puts n.go_floats   # 4.0
puts n.go_strs     # "ab"
