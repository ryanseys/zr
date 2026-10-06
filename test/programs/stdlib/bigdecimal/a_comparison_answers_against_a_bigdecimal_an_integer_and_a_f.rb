# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

p [BigDecimal("1.5") <=> 2, BigDecimal("1.5") == 1.5, BigDecimal("2") > 1, BigDecimal("1.5").eql?(1.5)]
p [1 + BigDecimal("0.5"), 1.5 + BigDecimal("1"), BigDecimal("1") + 0.5, BigDecimal("1") * 2r]
p BigDecimal("1.5").coerce(1)
p [BigDecimal("NaN") == BigDecimal("NaN"), BigDecimal("NaN") <=> 1, BigDecimal("Infinity") > 10**100]
p [BigDecimal("1.5") <=> "x", BigDecimal("1.5") == "x"]

