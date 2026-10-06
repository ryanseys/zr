# A Hash that a delete empties gives its table back, so memsize_of drops
# as CRuby's does, and the Hash works as a new one after it.
require "objspace"
h = {}
1000.times { |i| h[i] = true }
big = ObjectSpace.memsize_of(h)
1000.times { |i| h.delete(i) }
p ObjectSpace.memsize_of(h) < big / 10
p [h, h.size, h.empty?]
h[:a] = 1
h["b"] = 2
p h
p h.delete(:a), h.delete(:zz), h
g = { 1 => 2, 3 => 4 }
g.each { |k, _| g.delete(k) }
p g
g[5] = 6
p g, g[5], g.key?(1)
c = {}.compare_by_identity
k = "k"
c[k] = 1
c.delete(k)
c["k".dup] = 2
p c.compare_by_identity?, c.size
d = Hash.new(7)
d[1] = 1
d.delete(1)
p d[99]
