# In CRuby `0 == nil` is false -- only nil equals nil. A stored 0,
# also a 0 read from a Hash, is not nil, so `v != nil` is true.

# Pure int (no hash)
v = 0
puts (v == nil).inspect   # false
puts (v != nil).inspect   # true

w = 5
puts (w == nil).inspect   # false
puts (w != nil).inspect   # true

# Float / bool same.
f = 0.0
puts (f == nil).inspect   # false
puts (f != nil).inspect   # true

b = false
puts (b == nil).inspect   # false

# Hash<String,Int> stored 0 case reports != nil correctly.
h = {}
h["x"] = 0
h["y"] = 5
vx = h["x"]
vy = h["y"]
puts (vx == nil).inspect  # false
puts (vx != nil).inspect  # true
puts (vy == nil).inspect  # false
puts (vy != nil).inspect  # true

# Symmetric: nil == int is also false.
puts (nil == 0).inspect   # false
puts (nil != 0).inspect   # true
