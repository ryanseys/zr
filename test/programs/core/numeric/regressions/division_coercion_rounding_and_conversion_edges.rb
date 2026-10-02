# Edge cases of Integer, Rational, Complex and the Kernel conversions
# that answer as ruby's do.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

# Integer#div by a Float zero raises ZeroDivisionError; a Bignum
# receiver truncates its Float quotient.
t { 10.div(0.0) }
t { (2**64).div(0.0) }
t { 7.ceildiv(0.0) }
t { (-(2**64)).div(2.0**65) }
t { 10.div(-3.0) }

# fdiv names a Symbol as it inspects.
t { 7.fdiv(:sym) }

# remainder coerces an operand that is no Numeric first.
class Num
  def coerce(other) = [other.to_f, 2.0]
end
t { 5.remainder(Num.new) }

# Complex parts: a Complex with a zero imaginary part is real.
t { Complex(1, 0.0).to_r }
t { Rational(Complex(2.5, 0.0)) }

# The exception: keyword must be true or false.
t { Integer("1", exception: 0) }
t { Float("1", exception: nil) }
t { Rational(nil, exception: 0) }
t { Complex(nil, exception: 0) }

# to_r reads a leading run of zeros with underscores.
t { ["0_.1".to_r, "5.0_e2".to_r, "1_.5".to_r, "5.00_/3".to_r] }

# A zero denominator in a Complex string divides by zero.
t { Complex("1/0.0") }

# Random's seed converts with to_int.
t { Random.new(Rational(20, 2)).seed }
t { Random.new(Complex(20)).seed }
t { Random.new(Complex(20, 2)) }

# A negative count to max on a beginless range is an ArgumentError.
t { (..1.0).max(-1) }

# Integer#round ignores its keywords when it has no digits; the digits
# must fit an int; floor and ceil convert their digits first.
t { 1.round(half: :bogus) }
t { 1.round(foo: 1) }
t { 42.round(1 << 31) }
t { 1.ceil(half: :up) }
t { 1.floor("1") }
t { 15.round(-1, half: :even) }
t { Rational(5, 2).round(half: "even") }
t { Rational(5, 2).round(half: :bogus) }

# IO::Buffer integer types check their range.
t { IO::Buffer.new(8).set_value(:u64, 0, 2**64) }
t { IO::Buffer.new(8).set_value(:u64, 0, -2**63 - 1) }
t { IO::Buffer.new(8).set_value(:s64, 0, 2**63) }
t { IO::Buffer.new(8).set_value(:u32, 0, 2**32) }
t { IO::Buffer.new(8).set_value(:s32, 0, -2**31 - 1) }
t { IO::Buffer.new(8).set_value(:u16, 0, 65_536) }

# Complex(a, b) as nucomp_convert reads it: a Complex part with a zero
# imaginary part is real; a part that is no real raises.
t { Complex(Complex(1, 0.0), 1) }
t { Complex(Complex(1, 2), 3.0) }
t { Complex(1, Complex(2, 0.0)) }
t { Complex(Complex(1.0, 0), Complex(2, 0)) }
t { Complex("1", "2") }
t { Complex(false, 1) }
t { Complex(1, :a) }
t { Complex(1, :a, exception: false) }
t { Complex.rect(1, Complex(2)) }
t { Complex.rect(1, Complex(2, 1)) }
t { Complex.rect(Complex(1, 0.0), 2) }
t { Complex.polar(Complex(2), 0) }

# An infinite part times a zero part is a zero, as safe_mul makes it.
t { Float::INFINITY * Complex(0, 1) }
t { Complex(0, 1) * Float::INFINITY }
