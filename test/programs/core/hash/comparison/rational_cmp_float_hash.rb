# Rational value operations against a Float and as a Hash key. Rational(3, 2)
# is equal to 1.5: the Float is not truncated to 1/1. Equal Rationals have
# the same hash, so they find the same Hash entry.
# Each method keeps its second argument monomorphic (Float here) so the Float
# comparison path is exercised.
def cmpf(a, b); a <=> b; end
p cmpf(Rational(3, 2), 1.5)    # 0
p cmpf(Rational(3, 2), 2.0)    # -1
p cmpf(Rational(3, 2), 1.0)    # 1

def lt(a, b); a < b; end
def ge(a, b); a >= b; end
p lt(Rational(3, 2), 1.5)      # false
p lt(Rational(3, 2), 2.0)      # true
p ge(Rational(3, 2), 1.5)      # true

def eqf(a, b); a == b; end
p eqf(Rational(3, 2), 1.5)     # true
p eqf(Rational(1, 3), 0.3)     # false

# Comparison against another Rational / an Integer is unchanged.
def cmpr(a, b); a <=> b; end
p cmpr(Rational(1, 2), Rational(3, 4))  # -1
def cmpi(a, b); a <=> b; end
p cmpi(Rational(4, 2), 2)               # 0

# #hash is stable and equal Rationals share a Hash slot (reduced to lowest terms).
def stable(a); a.hash == a.hash; end
p stable(Rational(3, 4))       # true
p (Rational(3, 4).hash == Rational(6, 8).hash)   # true

h = { Rational(3, 4) => "three-quarters" }
p h[Rational(3, 4)]            # "three-quarters"
p h[Rational(6, 8)]           # "three-quarters"  (reduces to 3/4)
p h[Rational(1, 2)]           # nil
