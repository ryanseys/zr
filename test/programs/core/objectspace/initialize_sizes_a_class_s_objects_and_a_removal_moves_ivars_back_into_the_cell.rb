# `def initialize` gives its class objects with room for the variables that
# it writes, as rb_estimate_iv_count counts them, and an object whose
# variables moved out of its slot gets them back once a removal leaves
# few enough. ObjectSpace.dump shows the object's own class.
require "objspace"

def embedded?(o) = ObjectSpace.dump(o).include?('"embedded":true')
def class_of_dump(o) = ObjectSpace.dump(o)[/"class":"(0x\h+)"/, 1]
def address_of_dump(o) = ObjectSpace.dump(o)[/"address":"(0x\h+)"/, 1]

c = Class.new do
  attr_reader :a, :b, :c

  def initialize
    @a = nil
    @b = nil
    @c = nil
  end
end
o1 = c.new
o2 = c.new
p embedded?(o1)
o1.instance_variable_set(:@foo, 5)
o1.instance_variable_set(:@a, 0)
o1.instance_variable_set(:@b, 1)
o1.instance_variable_set(:@c, 2)
p embedded?(o1)
o1.remove_instance_variable(:@foo)
p embedded?(o1), o1.instance_variables, [o1.a, o1.b, o1.c]
o2.instance_variable_set(:@a, 0)
o2.instance_variable_set(:@b, 1)
o2.instance_variable_set(:@c, 2)
p embedded?(o2)

# The dump names an object's class, not the object.
p class_of_dump(o2) != address_of_dump(o2)
p class_of_dump(o2) == address_of_dump(c)
p class_of_dump(c.singleton_class) != address_of_dump(c)

# initialize's own writes count; a block's do not.
class Wide
  def initialize
    @a = @b = @c = @d = @e = @f = 1
    [1].each { @g = 2 }
  end
end
w = Wide.new
p embedded?(w), w.instance_variables.size
class Sub < Wide
  def initialize
    super
    @h = 1
  end
end
p embedded?(Sub.new)

