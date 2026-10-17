# BigDecimal's sum and difference as the C gives them: a zero operand
# gives the other, two zeros are negative only when both are, an operand
# far below the other only pushes the rounding when a precision is given
# (with no power of ten as wide as the gap), and infinities raise
# "results to" under EXCEPTION_INFINITY.
require "bigdecimal"

def show(label)
  value = yield
  puts "#{label}: #{value.inspect} #{value.sign}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

zero = BigDecimal("0")
none = 0 # an Integer operand
negative_zero = BigDecimal("-0")
show("0 + 0") { zero + none }
show("-0 + 0") { negative_zero + none }
show("-0 + -0") { negative_zero + negative_zero }
show("-0 - 0") { negative_zero - none }
show("-0 - -0") { negative_zero - negative_zero }
show("0 - 1") { zero - 1 }
show("1 + -0") { BigDecimal("1") + negative_zero }

huge = BigDecimal("0.1e#{(2**63) - 1}")
show("huge + 0") { huge + none }
show("huge - 0") { huge - none }
show("huge.add(0, 10)") { huge.add(BigDecimal(0), 10) }

big = BigDecimal("1e+1000000000000")
small = BigDecimal("1e-1000000000000")
show("big.add(small, 10)") { big.add(small, 10) }
show("small.sub(big, 10)") { small.sub(big, 10) }
show("small.add(0, 10)") { small.add(BigDecimal(0), 10) }
%i[down up half_even ceiling floor].each do |mode|
  BigDecimal.save_rounding_mode do
    BigDecimal.mode(BigDecimal::ROUND_MODE, mode)
    show("#{mode} big.add(small, 10)") { big.add(small, 10) }
    show("#{mode} big.sub(small, 10)") { big.sub(small, 10) }
    show("#{mode} -big.add(small, 10)") { (-big).add(small, 10) }
    show("#{mode} 1.5.add(1e-50, 1)") { BigDecimal("1.5").add(BigDecimal("1e-50"), 1) }
    show("#{mode} 1.5.sub(1e-50, 1)") { BigDecimal("1.5").sub(BigDecimal("1e-50"), 1) }
    show("#{mode} 25.add(-1e-90, 1)") { BigDecimal("25").add(BigDecimal("-1e-90"), 1) }
  end
end
show("1.25.add(1e-30, 40)") { BigDecimal("1.25").add(BigDecimal("1e-30"), 40) }

inf = BigDecimal("Infinity")
show("inf + inf") { inf + inf }
show("inf - inf") { inf - inf }
show("1 + inf") { BigDecimal("1") - inf }
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, true)
  show("inf + inf raises") { inf + inf }
  show("-inf + -inf raises") { -inf + -inf }
  show("1 - inf raises") { BigDecimal("1") - inf }
end
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_NaN, true)
  show("inf - inf raises") { inf - inf }
  show("nan + 1 raises") { BigDecimal("NaN") + 1 }
end
