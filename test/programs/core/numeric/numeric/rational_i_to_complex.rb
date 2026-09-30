# Rational#i -> Complex(0, self). The imaginary part keeps the exact Rational,
# as in CRuby.
p(Rational(3, 4).i)      # (0+(3/4)*i)
p(Rational(-1, 2).i)     # (0-(1/2)*i)
p(Rational(2, 1).i)      # (0+(2/1)*i)

r = Rational(3, 4)
c = r.i
p c.class                # Complex
p c.real                 # 0   -- the real part is exact
p c.imaginary            # (3/4)
# the VALUE also compares equal to the Float
p c.imaginary == 0.75
p c.abs2 == 0.5625
