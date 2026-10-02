# An operator whose operand is another float operator passes the inner
# double on without a Float. These check each case where the outer one
# needs the inner value as an object.

a = 1.5e300
b = 1.0e10
c = 2.0

# The inner result is not a flonum (too large, too small, zero).
p (a * b) / b
p (a * b) > 1.0
p 1.0 / (a * b)
p (1.0e-300 * 1.0e-20) * 1.0e20
p (c - c) * -1.0
p 1.0 / (c - c)

# The other operand is not a number, so the outer operator sends.
p (c * c) + 1r
p 1r + (c * c)
p (c * c) == 4
p (c + c) <=> 4.0

class Num
  def initialize(v) = @v = v
  def coerce(other) = [other, @v]
end
p (c * c) - Num.new(1.0)

# A receiver that a sending argument cannot change.
s = 1.0
pr = proc { s = 100.0 }
class Hook
  def initialize(pr) = @pr = pr
  def coerce(other)
    @pr.call
    GC.start
    [other, 2.0]
  end
end
h = Hook.new(pr)
p s + (c * h)
p s

# A string receiver held while the argument runs.
str = "ab"
p str * (1 + 2)

# A redefined Float operator is called for the inner and outer sites.
class Float
  alias_method :old_mul, :*
  def *(other)
    old_mul(other).old_mul(1.0) + 0.5
  end
end
p (c * c) * c
p 1.0 + (c * c)
