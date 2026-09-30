# `reduce(init, :+)` on a receiver of unknown type -- one of the two arrays
# `partition` answers -- folds it as an Array. The operator-symbol form
# carries no BLOCK, and it must still take the Array path, not the Hash path.
class Fixed
  attr_reader :units

  def initialize(units) = @units = units
  def +(other) = Fixed.new(@units + other.units)
  def *(other) = Fixed.new(@units * other.units)
  def negative? = @units.negative?
  def to_s = @units.to_s
end

deltas = [Fixed.new(3), Fixed.new(-2), Fixed.new(5)]
credits, debits = deltas.partition { |d| !d.negative? }

puts credits.reduce(Fixed.new(0), :+)
puts debits.reduce(Fixed.new(0), :+)
puts credits.inject(Fixed.new(1), :*)

# the block form on the same receiver, which already worked
puts credits.reduce(Fixed.new(0)) { |a, b| a + b }

# the seedless form, and Integers through the same shape
ns = [1, 2, 3, 4]
evens, odds = ns.partition(&:even?)
p evens.reduce(0, :+)
p evens.reduce(:+)
p odds.inject(:+)

# receivers that were never boxed keep answering
p ns.reduce(0, :+)
p ns.inject(:+)
p [[1, 2], [3]].map { |x| x.reduce(:+) }

# and a Hash really does take the face
h = { "a" => 1, "b" => 2 }
p h.reduce(0) { |s, (k, v)| s + v }
