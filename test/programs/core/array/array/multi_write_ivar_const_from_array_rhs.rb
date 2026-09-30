# A multi-write whose RHS is a non-literal expression that gives an
# Integer array (e.g. `.map { ... }`, a method call) assigns every
# target, ivars as well as locals.
#
# Example: `@a, @b = [10, 20].map { |x| x + 1 }` where the targets
# are ivars, so c.a / c.b return 11 / 21.

# (1) ivar targets, RHS is .map
class C1
  def initialize
    @a, @b = [10, 20].map { |x| x + 1 }
  end
  attr_reader :a, :b
end
c = C1.new
puts c.a              # 11
puts c.b              # 21

# (2) mixed: local + ivar from one Integer-array RHS.
class C2
  def initialize
    local, @i = [1, 2].map { |x| x * 10 }
    @captured_local = local
  end
  attr_reader :i, :captured_local
end
c2 = C2.new
puts c2.captured_local  # 10
puts c2.i               # 20

# (3) ivar targets where the RHS is a top-level method returning
# a fresh array. The RHS is a method call, not a literal ArrayNode.
def make_pair
  [7, 8]
end
class C3
  attr_reader :x, :y
  def initialize
    @x, @y = make_pair
  end
end
c3 = C3.new
puts c3.x   # 7
puts c3.y   # 8
