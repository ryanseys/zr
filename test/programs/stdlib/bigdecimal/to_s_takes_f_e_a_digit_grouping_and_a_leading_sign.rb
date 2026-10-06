# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

s = BigDecimal("1234.5678")
p [s.to_s("F"), s.to_s("E"), s.to_s(3), s.to_s("+"), s.to_s("3F")]
p BigDecimal("0.000012345").to_s("F")
p BigDecimal("1e30").to_s("F")
p BigDecimal("-1234.5678").to_s
p BigDecimal("-1234.5678").to_s("F")

