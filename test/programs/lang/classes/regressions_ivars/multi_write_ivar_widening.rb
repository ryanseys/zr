class T_multi_write_ivar_widening_Pair
  def initialize(a, b)
    @x, @y = [a, b]
  end
  attr_reader :x, :y
end

p = T_multi_write_ivar_widening_Pair.new("hello", "world")
puts p.x
puts p.y
