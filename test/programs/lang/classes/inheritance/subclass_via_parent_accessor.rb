# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# A parent method writes `self` into its own accessor.
# At exit: cycle leak: 1 objects (Column x1)
# A parent holds an accessor pointing at another object of the same family, and
# a parent method writes `self` into it. A read of it can call a method that
# only the subclass defines, with no NoMethodError.
#
# The parent and the subclass see the same inherited ivar in the same way.
# The call dispatches at run time, on the real object.
#
# Then `name` itself: a user READER owns the name just as a user method does,
# so Method#name and Class#name do not take the call.
class Node
  attr_accessor :right
  def initialize
    @right = self
  end

  def link(other)
    other.right = self
    self
  end
end

class Column < Node
  attr_accessor :name
  def initialize(name)
    super()
    @name = name
  end
end

root = Column.new("root")
Column.new("a").link(root)
p root.right.name
p root.right.class
p root.right.right.name

# the same shape with a method rather than a reader
class Node2
  attr_accessor :peer
  def attach(other)
    other.peer = self
    self
  end
end
class Leaf < Node2
  def initialize(v) = @v = v
  def value = @v
end
b = Leaf.new(2)
Leaf.new(1).attach(b)
p b.peer.value

# a plain reader named `name`, with no inheritance in sight
class Plain
  attr_reader :name
  def initialize(n) = @name = n
end
p Plain.new("x").name
p [Plain.new("y")].first.name
