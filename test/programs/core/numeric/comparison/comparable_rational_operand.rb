# A user class whose `<=>` takes a builtin operand, such as a Rational. The
# comparisons through Comparable use that `<=>`, and do not raise:
#
#   comparison of Fixed with Rational failed (ArgumentError)
#
# The user's own `<=>` comes before the Rational rule of the builtin
# comparison: that rule is for a numeric receiver, and a user object is not one.
class Fixed
  include Comparable
  attr_reader :units
  def initialize(units) = @units = units

  def <=>(other)
    return nil unless other.is_a?(Rational)

    @units <=> (other * 100).round
  end
end

p(Fixed.new(1999) < Rational(40, 2))
p(Fixed.new(1999) > Rational(40, 2))
p(Fixed.new(1999) <=> Rational(40, 2))
p(Fixed.new(2000) == Rational(20, 1))
p(Fixed.new(1999).between?(Rational(1, 1), Rational(100, 1)))
p [Fixed.new(300), Fixed.new(100)].map(&:units)

# an operand the guard rejects is CRuby's ArgumentError, as before
begin
  p(Fixed.new(1) < 5)
rescue ArgumentError => e
  p e.class
end

# a Time-typed operand takes an arm the same way
class Stamp
  include Comparable
  def initialize(t) = @t = t
  def <=>(other)
    return nil unless other.is_a?(Time)

    @t <=> other.to_i
  end
end
p(Stamp.new(100) < Time.at(200))
p(Stamp.new(300) <=> Time.at(200))
