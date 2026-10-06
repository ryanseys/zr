# coerce takes the numbers that meet a BigDecimal, and an error names a
# special constant by its inspect.
require "bigdecimal"
one = BigDecimal("1")
p one.coerce(2), one.coerce(1.5), one.coerce(Rational(1, 2)), (one.coerce("2") rescue $!)
[nil, true, :s, "x"].each { |o| p((one + o rescue $!)) }
p((one < "1" rescue $!), (BigDecimal("NaN") < 1), (BigDecimal("NaN") >= 1), one >= 1)
p BigDecimal.public_instance_methods(false).include?(:<), (one.to_d rescue $!)
