# The C keeps an exponent per nine-digit word in a signed word, so the
# decimal exponents run from EXPONENT_MIN to EXPONENT_MAX below. Text
# past them reads as infinite or zero, a result past them overflows or
# underflows, and EXCEPTION_OVERFLOW, EXCEPTION_UNDERFLOW and
# EXCEPTION_INFINITY turn each into a FloatDomainError.
require "bigdecimal"

max = ((2**63) - 1) / 9 * 9
min = (-(((2**63) - 8) / 9) * 9) - 8

def show(label)
  value = yield
  puts "#{label}: #{value.inspect} #{value.sign}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

show("0.1e max") { BigDecimal("0.1e#{max}") }
show("0.1e max+1") { BigDecimal("0.1e#{max + 1}") }
show("-0.1e max+1") { BigDecimal("-0.1e#{max + 1}") }
show("0.1e min") { BigDecimal("0.1e#{min}") }
show("0.1e min-1") { BigDecimal("0.1e#{min - 1}") }
show("-0.1e min-1") { BigDecimal("-0.1e#{min - 1}") }
show("0e max+9") { BigDecimal("0e#{max + 9}") }
show("1e huge") { BigDecimal("1e99999999999999999999999") }
show("1e -huge") { BigDecimal("1e-99999999999999999999999") }
show("0.0001e max+3") { BigDecimal("0.0001e#{max + 3}") }

huge = BigDecimal("0.1e#{max}")
tiny = BigDecimal("0.1e#{min}")
show("huge * 10") { huge * 10 }
show("-huge * 10") { -huge * 10 }
show("tiny / 10") { tiny / 10 }
show("-tiny / 10") { -tiny / 10 }
show("tiny * tiny") { tiny * tiny }
# The C counts a precision in a signed word, which wraps this far down.
p tiny.precision, tiny.scale, tiny.precision_scale, tiny.exponent
p BigDecimal("0.1e-1000000000").precision, huge.precision, huge.scale

BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, true)
  show("overflow: huge * 10") { huge * 10 }
  show("overflow: text") { BigDecimal("0.1e#{max + 1}") }
end
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_UNDERFLOW, true)
  show("underflow: tiny / 10") { tiny / 10 }
  show("underflow: text") { BigDecimal("0.1e#{min - 1}") }
end
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, true)
  show("infinity: -Infinity") { -BigDecimal("Infinity") }
  show("infinity: abs") { BigDecimal("-Infinity").abs }
end
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_NaN, true)
  show("nan: -NaN") { -BigDecimal("NaN") }
end
