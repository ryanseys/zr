# `a, b, c.x = expr` where one target is a setter call (`c.x =`)
# parses to a CallTargetNode in the targets list. The setter gets its
# value too.

class T_multi_write_setter_Box
  def initialize; @v = 0; end
  attr_accessor :v
end

class T_multi_write_setter_Holder
  def initialize
    @a = 0
    @b = 0
    @c = T_multi_write_setter_Box.new
  end
  def fill
    @a, @b, @c.v = [11, 22, 33]
  end
  def show
    puts @a
    puts @b
    puts @c.v
  end
end

h = T_multi_write_setter_Holder.new
h.fill
h.show
