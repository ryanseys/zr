# Kernel#BigDecimal as rb_convert_to_BigDecimal gives it: the checks of
# the precision and of `exception:`, a Float's digits (the shortest that
# read back, cut to 16, or rounded half-even to the precision), the shared
# zeros and infinities, a Rational with a precision of 0, a copy for a
# BigDecimal with a precision, and the cases that `exception: false`
# answers with nil.
require "bigdecimal"
require "bigdecimal/util"

def try
  value = yield
  p value
rescue => e
  p [e.class, e.message]
end

try { BigDecimal("1", nil) }
try { BigDecimal("1", "2") }
try { BigDecimal("1", 1.9) }
try { BigDecimal("1", -1) }
try { BigDecimal("1", -1, exception: false) }
try { BigDecimal(1, exception: 1) }
try { BigDecimal(1, exception: nil) }

try { BigDecimal(0.1 + 0.2) }
try { BigDecimal(123456789.123456789) }
try { BigDecimal(1.0e20) }
try { BigDecimal(1.0e-20) }
try { BigDecimal(5e-324) }
try { BigDecimal(1.7976931348623157e308) }
try { BigDecimal(2.5, 1) }
try { BigDecimal(0.125, 2) }
try { BigDecimal(-0.1234567, 4) }
try { BigDecimal(0.01, 16) }
try { BigDecimal(0.1, 17) }
try { BigDecimal(0.1, 17, exception: false) }
try { [BigDecimal(0.0).equal?(BigDecimal(0.0)), BigDecimal(-0.0).equal?(BigDecimal(-0.0)), BigDecimal(-0.0).sign] }
try { [BigDecimal(Float::INFINITY).equal?(BigDecimal::INFINITY), BigDecimal(Float::NAN).equal?(BigDecimal::NAN)] }
try { BigDecimal(-Float::INFINITY).equal?(BigDecimal(-Float::INFINITY)) }
try { BigDecimal("Infinity").equal?(BigDecimal("Infinity")) }
try { [0.5.to_d, (-0.0).to_d.sign, 9.05.to_d.to_s("F"), Math::PI.to_d.to_f] }

try { BigDecimal(Rational(5, 4)) }
try { BigDecimal(Rational(5, 4), exception: false) }
try { BigDecimal(355.quo(113), 0) }
try { [Rational(5, 4).to_d, 355.quo(113).to_d, 355.quo(113).to_d(0)] }
try { 355.quo(113).to_d(-42) }
try { BigDecimal(1.quo(3), 21) }

try { BigDecimal(Complex(1, 0)) }
try { BigDecimal(Complex(1, -0.0)) }
try { BigDecimal(Complex(1.quo(3), 0), 21) }
try { BigDecimal(Complex(1, 1)) }
try { BigDecimal(Complex(1, 1), exception: false) }
try { [Complex(1, 0).to_d, Complex(0.1234567, 0).to_d, Complex(0.1234567, 0).to_d(4)] }

bd = BigDecimal("1.12", 1)
try { [BigDecimal(bd).equal?(bd), BigDecimal(bd, 1).equal?(bd), BigDecimal(bd, 1) == bd] }

try { BigDecimal(nil) }
try { BigDecimal(true) }
try { BigDecimal(:test) }
try { BigDecimal(Object.new) }
try { BigDecimal(nil, exception: false) }
try { BigDecimal(:test, exception: false) }
try { BigDecimal("1\0", exception: false) }
try { BigDecimal("x", exception: false) }
try { BigDecimal(".", exception: false) }
try { BigDecimal("1\0") }

BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_NaN, true)
  try { BigDecimal(Float::NAN) }
  try { BigDecimal(BigDecimal::NAN) }
  try { BigDecimal("NaN", exception: false) }
end
