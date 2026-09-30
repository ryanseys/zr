# Multiple assignment from #deconstruct of a Data/Struct value read out of an
# Array: deconstruct answers the member values (an Array), and the
# assignment spreads them.
V = Data.define(:x, :y)
first = [V.new(1, 2)].first
a, b = first.deconstruct
p [a, b]
p first.deconstruct
S = Struct.new(:m, :n)
s = [S.new(5, 6), S.new(7, 8)].last
c, d = s.deconstruct
p [c, d]
