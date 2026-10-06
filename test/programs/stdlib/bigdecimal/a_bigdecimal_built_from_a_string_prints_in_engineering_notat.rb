# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

p [BigDecimal("1.5"), BigDecimal("1.5").to_s, BigDecimal("1.5").inspect]
p [BigDecimal("-0.003"), BigDecimal("123456789.123456789"), BigDecimal("1e100")]
p [BigDecimal("0"), BigDecimal("-0"), BigDecimal("0").to_s]
p [BigDecimal("Infinity"), BigDecimal("-Infinity"), BigDecimal("NaN")]
p [BigDecimal(42), BigDecimal(-7), BigDecimal(10**30)]
p [BigDecimal(3.14), BigDecimal(3.14, 3), BigDecimal(1.5, 2), BigDecimal(1e100)]
p BigDecimal(Rational(1, 3), 5)
p [BigDecimal("1_000"), BigDecimal(" 1.5 "), BigDecimal(".5"), BigDecimal("1.5e3")]
p [BigDecimal("1.5").class, BigDecimal("1.5").frozen?]

