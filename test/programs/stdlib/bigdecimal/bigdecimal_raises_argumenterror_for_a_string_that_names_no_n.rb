# bigdecimal -- the native core: construction, engineering-notation to_s,
# exact arithmetic, division to the documented precision rule, rounding
# modes, mode/limit state, conversions, and the error shapes.
require "bigdecimal"

begin
  BigDecimal("bogus")
rescue ArgumentError => e
  p [e.class, e.message]
end
begin
  BigDecimal(nil)
rescue TypeError => e
  p [e.class, e.message]
end
begin
  BigDecimal(0.1, 20)
rescue ArgumentError => e
  p [e.class, e.message]
end
begin
  BigDecimal(Rational(1, 3))
rescue ArgumentError => e
  p [e.class, e.message]
end
p [BigDecimal("1.5", exception: false), BigDecimal("x", exception: false), BigDecimal(nil, exception: false)]

