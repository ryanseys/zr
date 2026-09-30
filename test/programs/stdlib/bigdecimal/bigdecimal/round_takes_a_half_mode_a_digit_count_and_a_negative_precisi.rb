# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

p [BigDecimal("2.5").round, BigDecimal("2.5").round(half: :even), BigDecimal("2.345").round(2, :down)]
p [BigDecimal("1.23456789").round(3), BigDecimal("123.45").round(-1)]
p [BigDecimal("3.7").floor, BigDecimal("3.2").ceil, BigDecimal("-3.7").truncate]
p [BigDecimal("2.5").ceil(1).class, BigDecimal("2.5").ceil.class, BigDecimal("123.45").round(-1).class]
p [BigDecimal("3.75").fix, BigDecimal("3.75").frac, BigDecimal("-1.5").abs]

