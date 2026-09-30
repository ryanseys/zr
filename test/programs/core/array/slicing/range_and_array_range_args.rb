# Methods that take a Range argument where an Integer can also go:
#   rand(range) / rand(float)
#   Range#cover? with a Range argument
#   Range#first(n) / #last(n) / #count
#   Array#values_at with a Range argument
#   Array#fill(value, range)

# rand with a range / float arg. Values are nondeterministic,
# so assert membership rather than the value.
vi = rand(1..6)
puts(vi >= 1 && vi <= 6)
puts vi.class
vf = rand(1.0..10.0)
puts(vf >= 1.0 && vf < 10.0)
puts vf.class

# cover? with a Range argument
puts (1..10).cover?(5..8)
puts (1..10).cover?(5..12)
puts (1..10).cover?(5)

# first(n) / last(n) / count
p (1..10).first(3)
p (1..10).last(3)
p (1...10).last(3)
p (1..10).first(20)
puts (1..10).count
puts (1...10).count

# values_at with a Range argument
p [10, 20, 30, 40, 50].values_at(1..3)
p [10, 20, 30, 40, 50].values_at(0, 2, 4)
p ["a", "b", "c", "d"].values_at(1..2)

# fill(value, range)
a = [1, 2, 3, 4, 5]
a.fill(0, 2..4)
p a
b = [1, 2, 3, 4, 5]
b.fill(9, 1...3)
p b
