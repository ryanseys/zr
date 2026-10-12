# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

# The SHAPE, not the number: zr vendors bigdecimal's latest upstream release
# (vendor/ext/bigdecimal) and the oracle reads the copy ruby ships.
p BigDecimal::VERSION.match?(/\A\d+\.\d+\.\d+\z/)
p [BigDecimal::BASE, BigDecimal.double_fig]
p [BigDecimal::ROUND_MODE, BigDecimal.mode(BigDecimal::ROUND_MODE), BigDecimal.mode(BigDecimal::EXCEPTION_ALL), BigDecimal.limit]

