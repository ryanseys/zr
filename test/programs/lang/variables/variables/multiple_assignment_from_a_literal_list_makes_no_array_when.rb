# `a, b = x, y` as a statement assigns from the list with no Array
# made and taken apart, as CRuby's compiler does when the value is
# popped; every shape of target still reads as if it had been.
a, b = 1, 2
a, b = b, a
p [a, b]
c, d, e = 1, 2
p [c, d, e]
f, g = 1, 2, 3
p [f, g]
h, *i = 1, 2, 3
p [h, i]
j, *k = 1
p [j, k]
l, * = 1, 2
p l
*m, n = 1, 2, 3
p [m, n]
(o, q), r = [1, 2], 3
p [o, q, r]
s, (t, *u) = 1, [2, 3, 4]
p [s, t, u]
class Pt
  attr_accessor :x, :y
  def initialize; @x, @y = 1, 2; end
  def swap; @x, @y = @y, @x; self; end
  def [](k) = instance_variable_get(k)
  def []=(k, v); instance_variable_set(k, v); end
end
pt = Pt.new.swap
p [pt.x, pt.y]
pt.x, pt.y = pt.y, pt.x
p [pt.x, pt.y]
pt[:@x], pt[:@y] = 8, 9
p [pt.x, pt.y]
# The targets' receivers, then the list, then the writes, in order.
log = []
obj = Object.new
obj.define_singleton_method(:x=) { |v| log << [:x, v] }
obj.define_singleton_method(:y=) { |v| log << [:y, v] }
(log << :recv; obj).x, (log << :recv2; obj).y = (log << :one; 1), (log << :two; 2)
p log
# A loop turns with no Array a turn.
def swaps(n)
  a = 1; b = 2; i = 0
  while i < n
    a, b = b, a
    i += 1
  end
  [a, b]
end
swaps(10)
before = GC.stat(:total_allocated_objects)
r = swaps(10_001)
made = GC.stat(:total_allocated_objects) - before
p r
p made < 10
# In value position the list is the value.
v = (w, z = 3, 4)
p [v, w, z]
def last; a, b = 5, 6; end
p last
