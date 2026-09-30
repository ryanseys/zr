r = Rational(3, 2)
p r.finite?
p r.infinite?
p r.coerce(2)
p r.coerce(2.0)
p r.div(1)
p Rational(7, 2).div(2)
p r.i
c = Complex(6, 0)
p c.finite?
p c.infinite?
p c.to_f
p c.to_i
p c.to_r
p c.coerce(3)
p Complex(3, 4).finite?
p Complex(3, 4).numerator
p Complex(3, 4).denominator
p Complex(Rational(2, 3), Rational(3, 4)).numerator
p Complex(Rational(2, 3), Rational(3, 4)).denominator
begin
  Complex(3, 4).to_f
rescue RangeError => e
  puts e.message
end
