# Rational defines neither the comparisons nor div, modulo, remainder,
# divmod, eql?, zero? and integer?: Comparable and Numeric answer them
# over Rational's own <=>, / and floor, as CRuby's nurat leaves them.

p Rational(7, 2) % 1.5, Rational(7, 2).divmod(Rational(1, 3)), Rational(-7, 2).remainder(2)
p Rational(1, 2) < 1, Rational(1, 2) >= 0.5, Rational(0).zero?, Rational(1, 2).integer?
p Rational(1, 2).eql?(Rational(1, 2)), Rational(1, 2).eql?(0.5)
p Rational(5, 3).div(Rational(1, 2)), Rational(5, 3).modulo(2), Rational(-5, 3).divmod(2)
[-> { Rational(1, 2) < "a" }, -> { Rational(1, 2) % 0.0 }, -> { Rational(1, 2).div(0) }].each do |bad|
  bad.call
rescue => e
  p e
end
p Rational.public_instance_methods(false).sort
p Rational.instance_method(:<).owner, Rational.instance_method(:div).owner

