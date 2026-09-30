# A class defining `abs` (or `round`, `succ`) shares that name with Integer.
# A call to `abs` on an ivar that holds an Integer still goes to Integer#abs,
# and a call on a Fixed goes to Fixed#abs.
class Fixed
  attr_reader :units

  def initialize(units) = @units = units
  def abs = Fixed.new(@units.abs)
  def round = Fixed.new(@units.round)
  def succ = Fixed.new(@units.succ)
  def coerce(other) = [Fixed.new(other), self]

  def probe
    p @units.abs
    p @units.round
    p @units.succ
    p @units.ceil
    p @units.floor
    p @units.truncate
  end
end

Fixed.new(-1999).probe
p Fixed.new(-7).abs.units
p Fixed.new(3).succ.units

# the user method still wins for its own instances
f = [Fixed.new(-2)][0]
p f.abs.units
