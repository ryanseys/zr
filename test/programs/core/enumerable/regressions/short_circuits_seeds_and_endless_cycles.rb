# Edge cases of Enumerable that answer as ruby's do.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

# one? stops at the second match.
seen = []
t { [(1..3).one? { |x| seen << x; x > 0 }, seen] }

# cycle streams its first round, so an endless source works; its count
# is an Integer.
i = 0
t { Enumerator.new { |y| loop { y << (i += 1) } }.cycle.first(3) }
t { (1..2).cycle(false) { } }
t { {a: 1}.cycle(false) { } }
t { (1..2).cycle(2).to_a }

# inject names its argument count, and a second argument must be a
# Symbol or a String.
t { [1, 2].inject }
t { [1].inject(:+, 2) }
t { [1, 2].inject(1, 2, 3) }

# sum adds a seed that is not an Integer as ruby's Integer#+ does.
t { (1..3).sum(Rational(1, 2)) }
t { (1..3).sum("1.5") }
t { (1..3).sum("x") }
t { (1..3).sum(nil) }

# A recursive Set has a hash.
require "set"
s = Set.new
s << s
t { s.hash.class }

# Hash#== asks an operand with to_hash.
class HashLike
  def to_hash = {a: 1}
  def ==(other) = other == {a: 1}
end
t { {a: 1} == HashLike.new }
t { {b: 1} == HashLike.new }
