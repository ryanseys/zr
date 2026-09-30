# `@a, @b = expr1, expr2` (multi-write to ivars) sets each ivar, for
# Integer values and for objects.

class T_multi_write_ivar_Inner
  def initialize(x); @x = x; end
  attr_reader :x
end

class T_multi_write_ivar_HasObjects
  def initialize
    @left, @right = T_multi_write_ivar_Inner.new(7), T_multi_write_ivar_Inner.new(8)
  end
  def sum
    @left.x + @right.x
  end
end

class T_multi_write_ivar_Holder
  def initialize
    @a, @b = 1, 2
  end
  attr_reader :a, :b
  def has_obj
    T_multi_write_ivar_HasObjects.new.sum
  end
end

h = T_multi_write_ivar_Holder.new
puts h.a
puts h.b
puts h.has_obj
