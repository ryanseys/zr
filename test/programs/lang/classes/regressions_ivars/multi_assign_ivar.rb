class T_multi_assign_ivar_A
  attr_reader :x
  def initialize; @x = 11; end
end
class T_multi_assign_ivar_B
  attr_reader :y
  def initialize; @y = 22; end
end
class T_multi_assign_ivar_C
  attr_reader :z
  def initialize; @z = 33; end
end

class T_multi_assign_ivar_Driver
  def self.load
    a = T_multi_assign_ivar_A.new
    b = T_multi_assign_ivar_B.new
    c = T_multi_assign_ivar_C.new
    return a, b, c
  end
end

class T_multi_assign_ivar_Holder
  def initialize
    @a, @b, @c = T_multi_assign_ivar_Driver.load
  end
  def show
    puts "a.x=#{@a.x} b.y=#{@b.y} c.z=#{@c.z}"
  end
end

h = T_multi_assign_ivar_Holder.new
h.show
