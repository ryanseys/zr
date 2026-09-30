# An empty `Range#sum { block }` whose block value is a product of Floats
# read from nested Arrays. The sum uses the block, so it is the Integer 0,
# and the division gives a Float.
aug = [[2.0, 3.0, 0.0]]
x = Array.new(1, 0.0)
s = (1...1).sum { |j| aug[0][j] * x[j] }
x[0] = (aug[0][1] - s) / aug[0][0]
p x
# non-empty range sum with a block
t = (0...2).sum { |j| aug[0][j] * 2 }
p t
