# A Rational or Complex receiver that reaches an operator or a numeric method
# through a block parameter keeps its own arithmetic. `**` and `%` do not
# fall back to Float, and divmod / modulo / quo / abs work as for any Rational.
p([Rational(3, 2)].map { |a| a**2 })
p([Rational(7, 2)].map { |a| a % 2 })
p([Rational(-7, 2)].map { |a| a**3 })
p([Complex(1, 2)].map { |a| a**2 })
p([Complex(1, 2)].map { |a| a**3 })

p([Rational(7, 2)].map { |a| a.divmod(2) })
p([Rational(7, 2)].map { |a| a.modulo(2) })
p([Rational(7, 2)].map { |a| a.quo(2) })
p([Rational(-7, 2)].map { |a| a.abs })
p([Rational(7, 2)].map { |a| a.abs })

# other Rational methods, as controls
p([Rational(7, 2)].map { |a| a.floor })
p([Rational(7, 2)].map { |a| a.round })
p([Rational(7, 2)].map { |a| a.truncate })
p([Rational(7, 2)].map { |a| a.to_i })
p([Rational(3, 2)].map { |a| a + 1 })
p([Rational(3, 2)].map { |a| a * 2 })
p([Rational(3, 2)].map { |a| a / 2 })
p([Rational(3, 2)].map { |a| a - 1 })

# and the same operators on the kinds that share the path
p([2].map { |a| a**3 })
p([7].map { |a| a % 2 })
p([7].map { |a| a.divmod(2) })
p([7].map { |a| a.quo(2) })
p([-7].map { |a| a.abs })
p([2.5].map { |a| a**2 })
p([7.5].map { |a| a % 2 })
p([7.5].map { |a| a.divmod(2) })
p([-7.5].map { |a| a.abs })

# a monomorphic receiver was always exact; it has to stay that way
r = Rational(3, 2)
p r**2
p r % 1
p r.divmod(1)
p r.quo(2)
p r.abs
