# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

p BigDecimal.interpret_loosely("1.5whatever")
p BigDecimal.interpret_loosely("junk")
