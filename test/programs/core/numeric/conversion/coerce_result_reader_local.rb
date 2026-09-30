# Read an ivar off an operator result that only the coerce route makes, and
# assign it to a local. The ivar holds a Rational, a Complex, an Integer or a
# Float, and the local gets that value.
class Q
  attr_reader :v
  def initialize(v); @v = v; end
  def self.scalar(v); new(v); end
  def coerce(other); [Q.scalar(other), self]; end
  def *(other); Q.new(@v * other.v); end
end

v1 = (2 * Q.new(Rational(3, 2))).v
p v1
p v1.class

# the neighbouring forms that already worked stay working
p((2 * Q.new(Rational(3, 2))).v)
q1 = (2 * Q.new(Rational(3, 2)))
p q1.v
t = Q.new(Rational(5, 4))
p t.v
p (Q.new(Rational(1, 2)) * Q.new(Rational(2, 3))).v

class C
  attr_reader :v
  def initialize(v); @v = v; end
  def self.scalar(v); new(v); end
  def coerce(other); [C.scalar(other), self]; end
  def *(other); C.new(@v * other.v); end
end

v2 = (2 * C.new(Complex(1, 2))).v
p v2
p v2.class
p((2 * C.new(Complex(1, 2))).v)

# a scalar ivar takes the same route
class I
  attr_reader :v
  def initialize(v); @v = v; end
  def self.scalar(v); new(v); end
  def coerce(other); [I.scalar(other), self]; end
  def *(other); I.new(@v * other.v); end
end

p (2 * I.new(4)).v
p (2.0 * I.new(2.5)).v

# and using the local afterwards: each operator on it answers a value of the
# correct type.
w = (2 * Q.new(Rational(3, 2))).v
p w + 1
p w - 1
p w * 2
p w + Rational(1, 2)
p w - Rational(1, 2)
p w * Rational(1, 3)
p w + 1.5
p w * 0.5
p w.class
p (w + Rational(1, 2)).class
p (w + 1.5).class

c = (2 * C.new(Complex(1, 2))).v
p c + 1
p c * 2
p c.class
p (c + 1).class
