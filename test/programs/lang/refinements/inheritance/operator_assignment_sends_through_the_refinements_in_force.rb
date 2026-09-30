# An operator assignment on an attribute or an index -- `recv.name op= v`,
# `recv[i] op= v`, their `||=` and `&&=`, and `&.` -- reads, writes and
# operates through the refinements in force, as each send alone would.
class Base
  def initialize = @v = 1
  def [](i) = @v
end
class Leaf < Base; end
module Setters
  refine Base do
    def v = @v
    def v=(x)
      @v = x
    end
    def []=(i, x)
      @v = x
    end
  end
  refine Integer do
    def plus_one = self + 1
  end
end
using Setters
l = Leaf.new
l.v = 5
p l.v
l.v += 1
p l.v
l.v ||= 0
l.v &&= l.v * 2
p l.v
l[0] += 3
p l[0]
l&.v -= 1
p l.v
p(l.send(:v=, 9))

