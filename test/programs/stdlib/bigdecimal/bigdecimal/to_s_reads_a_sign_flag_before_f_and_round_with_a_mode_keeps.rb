require "bigdecimal"
x = BigDecimal("12345.678")
p x.to_s("+F"), x.to_s(" F"), x.to_s("+3F"), x.to_s("E"), x.to_s(3)
p x.to_s.encoding, x.inspect.encoding
p BigDecimal("2.5").round(0, :half_even), BigDecimal("2.5").round, BigDecimal("2.5").round(half: :even)
