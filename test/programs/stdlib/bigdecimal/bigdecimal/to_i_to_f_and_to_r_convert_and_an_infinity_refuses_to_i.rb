# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

p [BigDecimal("1.5").to_i, BigDecimal("1.5").to_f, BigDecimal("1.5").to_r]
begin
  BigDecimal("Infinity").to_i
rescue FloatDomainError => e
  p [e.class, e.message]
end
p [BigDecimal("1.5").zero?, BigDecimal("0").zero?, BigDecimal("1.5").nonzero?, BigDecimal("0").nonzero?]
p [BigDecimal("1.5").finite?, BigDecimal("NaN").nan?, BigDecimal("-Infinity").infinite?]
p [BigDecimal("-1.5").sign, BigDecimal("0").sign, BigDecimal("NaN").sign, BigDecimal("Infinity").sign]
p [BigDecimal("123.45").exponent, BigDecimal("123.45").precision, BigDecimal("123.45").n_significant_digits]
p [BigDecimal("1e20").precision, BigDecimal("1e-20").precision, BigDecimal("100").precision]
p BigDecimal("123.45").split
p BigDecimal("123.45").precision_scale

