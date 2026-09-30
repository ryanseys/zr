# The coerce route makes two calls that do not appear in the source: the
# operator, and #coerce itself. The parameter of coerce gets the Integer,
# Rational or Float on the left, and passes it to the factory. An explicit
# `m.coerce(4)` call is the second shape. Both shapes are here, each in its
# own class so the other's call sites cannot mask it.
class Fac
  attr_reader :v

  def initialize(v)
    @v = v
  end

  def self.scalar(v)
    new(v)
  end

  def coerce(other)
    [Fac.scalar(other), self]
  end

  def +(other)
    o = other.is_a?(Fac) ? other : Fac.scalar(other)
    Fac.new(@v + o.v)
  end

  def to_s
    "F(" + @v.to_s + ")"
  end
end

# coerce-only: no direct call site to bind anything
puts (10 + Fac.new(Rational(3, 2))).to_s
puts (2 + Fac.new(5)).to_s
puts (1.5 + Fac.new(2.5)).to_s

class Exp
  attr_reader :v

  def initialize(v)
    @v = v
  end

  def coerce(other)
    [Exp.new(other), self]
  end

  def *(other)
    o = other.is_a?(Exp) ? other : Exp.new(other)
    Exp.new(@v * o.v)
  end

  def to_s
    "E(" + @v.to_s + ")"
  end
end

# an explicit coerce call alongside an operator-routed one
m = Exp.new(3)
p m.coerce(4).map(&:to_s)
puts (2 * m).to_s
puts (m * 2).to_s
