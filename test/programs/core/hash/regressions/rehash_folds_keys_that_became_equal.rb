# rehash folds keys that came to be eql? into the first one, which takes
# the last value, as ruby builds the table again.
x = [1]
y = [2]
z = [3]
h = {x => :x, "s" => 0, y => :y, z => :z}
y[0] = 1
z[0] = 1
h.rehash
p h, h.size, h[[1]], h.keys

w = [9]
g = {w => :w}.compare_by_identity
w[0] = 8
p g.rehash.size, g[w]
