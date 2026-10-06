# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

p BigDecimal("2") + BigDecimal("3.5")
p BigDecimal("2") * BigDecimal("3.5")
p BigDecimal("1") / BigDecimal("3")
p BigDecimal("10") / 3
p BigDecimal("100") / BigDecimal("7")
p BigDecimal("1") / BigDecimal("3.00000000000000000001")
p BigDecimal("1.2345") / 3
p BigDecimal(1) / 0
p BigDecimal("1e50") + 1
p [BigDecimal("1.23456").mult(BigDecimal("2.34567"), 4), BigDecimal("1.23456").add(BigDecimal("2.34567"), 4), BigDecimal("1.23456").sub(BigDecimal("2.34567"), 4)]
p [BigDecimal("10").div(3), BigDecimal("10").div(3, 5), BigDecimal("10").div(3).class]
d = BigDecimal("10").divmod(3)
p [d, d[0].class, d[1].class]
p [BigDecimal("-10").divmod(3), BigDecimal("-10") % 3, BigDecimal("-10").remainder(3)]
p [BigDecimal("10.5") % 3, BigDecimal("10.5").divmod(3)]

