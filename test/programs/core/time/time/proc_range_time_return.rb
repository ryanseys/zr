# A proc/lambda can return a Range or a Time, and the caller gets the same
# value. Step-ranges (downto) keep their direction.
f = ->(n) { (1..n) }
r = f.call(3)
p r
p r.to_a
p f.call(5).sum
g = proc { |a, b| (a...b) }
p g.call(2, 6).to_a
h = ->() { Time.at(0) }
t = h.call
p t.class
p t.to_i
make = ->(n) { n.downto(1) }
p make.call(3).to_a
