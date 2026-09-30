p 42.size
p (2**64).size
p (2**64 - 1).size
p (2**128).size
p 0.3.rationalize
p 2.5.rationalize
p 3.14159.rationalize
p 1.333.rationalize(0.01)
p Rational(2.5)
p Rational(1.5, 0.5)
begin
  Complex(nil)
rescue TypeError => e
  puts e.message
end
p 2 ** Complex(0, 1)
p Complex(6, 0).to_r
p Complex(3, 4).numerator
p 7.div(Rational(2))
p 10.div(Rational(3, 2))
