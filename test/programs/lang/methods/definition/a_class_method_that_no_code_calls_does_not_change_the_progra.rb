# A class method that no code calls has a body with a bare
# `new(args)` that does not agree with the arity of `initialize`.
# The program does not call it, so it runs as if the method were
# not there.

# Variant 1: one class. No code calls Base.create, and
# Base#initialize takes no argument.
class Base
  def initialize
    @x = 1
  end
  def x; @x; end

  def self.create(attrs)
    new(attrs)
  end
end

b = Base.new
puts b.x                               # 1

# Variant 2: three classes, and the program calls create only on
# the leaf.
class Base2
  def initialize
    @v = 0
  end

  def self.create(attrs)
    new(attrs)
  end
end

class Mid < Base2
end

class Leaf < Mid
  def initialize(x)
    @x = x
  end
  def x; @x; end
end

# `Leaf.create(42)` runs the body of Base2.create, where `new(attrs)`
# is `Leaf.new(42)` and calls Leaf#initialize(42).
puts Leaf.create(42).x                 # 42

# Variant 3: an initialize with a default argument, and a create
# that no code calls.
class Base3
  def initialize(attrs = {})
    @v = attrs.length
  end
  def v; @v; end

  def self.create(attrs)
    new(attrs)
  end
end

# An explicit `Base3.new` still works.
b3 = Base3.new
puts b3.v                              # 0
