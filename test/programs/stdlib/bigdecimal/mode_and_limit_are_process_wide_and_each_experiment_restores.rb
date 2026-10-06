# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

# Mode and limit are process-wide; each experiment restores what it touched.
begin
  BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, true)
  BigDecimal(1) / 0
rescue FloatDomainError => e
  p [e.class, e.message]
ensure
  BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)
end
begin
  BigDecimal.mode(BigDecimal::EXCEPTION_NaN, true)
  BigDecimal("NaN") + 1
rescue FloatDomainError => e
  p [e.class, e.message]
ensure
  BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
end
p BigDecimal.limit(5)
p BigDecimal("1") / BigDecimal("3")
p BigDecimal("2") + BigDecimal("1.111111111")
BigDecimal.limit(0)
p BigDecimal.save_limit {
  BigDecimal.limit(3)
  BigDecimal("1") / BigDecimal("3")
}
p BigDecimal.limit
p BigDecimal.save_rounding_mode {
  BigDecimal.mode(BigDecimal::ROUND_MODE, :down)
  BigDecimal("2.789").round(1)
}
p BigDecimal.mode(BigDecimal::ROUND_MODE)
p BigDecimal.mode(BigDecimal::ROUND_MODE, :half_even)
p BigDecimal("0.25").round(1)
BigDecimal.mode(BigDecimal::ROUND_MODE, :half_up)

