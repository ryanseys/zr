# frozen_string_literal: true

# Float: the constants, and the methods written over the kernel's
# arithmetic.
class Float
  # NUM2LONG's refusal of a Float past the machine word.
  def index_range_error
    Primitive.attr! :hidden
    raise RangeError, format("float %-.10g out of range of integer", self)
  end
  private :index_range_error

  INFINITY = 1.0 / 0.0
  NAN = 0.0 / 0.0
  EPSILON = 2.220446049250313e-16
  MAX = 1.7976931348623157e+308
  MIN = 2.2250738585072014e-308
  DIG = 15
  MANT_DIG = 53
  RADIX = 2
  MIN_EXP = -1021
  MAX_EXP = 1024
  MIN_10_EXP = -307
  MAX_10_EXP = 308

  def to_f = self
  def zero? = self == 0.0
  def positive? = self > 0.0
  def negative? = self < 0.0
  # A negative count of digits rounds the Integer the value becomes.
  def floor(digits = 0)
    digits = Primitive.zr_index_operand_m(digits)
    return Primitive.zr_flo_floor_m(self, 0).floor(digits) if digits < 0

    Primitive.zr_flo_floor_m(self, digits) || exactly(digits, :floor)
  end

  def ceil(digits = 0)
    digits = Primitive.zr_index_operand_m(digits)
    return Primitive.zr_flo_ceil_m(self, 0).ceil(digits) if digits < 0

    Primitive.zr_flo_ceil_m(self, digits) || exactly(digits, :ceil)
  end

  def truncate(digits = 0) = self > 0 ? floor(digits) : ceil(digits)
  def fdiv(other) = self / other
  def quo(other) = self / other

  # The quotient and the modulo, as CRuby's flodivmod pairs them; an
  # operand it does not know coerces, as flo_divmod hands it on.
  def divmod(other)
    other = other.to_f if other.is_a?(Integer)
    return Primitive.zr_num_coerce_m(self, other, :divmod, 0) unless other.is_a?(Float)
    raise ZeroDivisionError, +"divided by 0" if other == 0.0

    [Primitive.zr_float_quotient_value(self, other).to_i, self % other]
  end

  alias to_int to_i

  # `Float(other)` beside self, so a String parses and anything with
  # no to_f is refused as Float() refuses it.
  def coerce(other)
    return [other, self] if other.is_a?(Float)
    return [other.to_f, self] if other.is_a?(Integer) || other.is_a?(Rational)

    [Float(other), self]
  end
end

module Kernel
  # `Float(value)`: a Float, an Integer converted, or a String parsed
  # strictly.
  def Float(arg, exception: true)
    Primitive.attr! :ruby
    value = arg
    case value
    when Float then value
    when Integer then value.to_f
    when String
      result = Primitive.zr_str_to_f_strict(value)
      return result if result || !exception

      raise ArgumentError, "invalid value for Float(): #{value.inspect}"
    when nil, true, false
      return nil unless exception

      raise TypeError, "can't convert #{value.inspect} into Float"
    else
      return value.to_f if value.respond_to?(:to_f)
      return nil unless exception

      raise TypeError, "can't convert #{conversion_name(value)} into Float"
    end
  end

  private :Float
  module_function :Float
end

class String
  def to_f = Primitive.zr_str_to_f(self)
end

# The libm functions, over doubles; an Integer argument converts.
module Math
  PI = 3.141592653589793
  E = 2.718281828459045

  # Each function is a private method too, for `include Math`.
  module_function

  # A Float or an Integer in the domain is answered by the kernel at
  # once (zr_math_sqrt_fast); anything else takes the checks, which
  # convert or refuse it.
  def sqrt(x)
    r = Primitive.zr_math_sqrt_fast(x)
    return r if r

    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - sqrt" if x < 0.0
    return 0.0 if x == 0.0

    Primitive.zr_math_sqrt(x)
  end

  def cbrt(x) = Primitive.zr_math_call_fast(1, x) || Primitive.zr_math_call(1, check(x), 0.0)
  def sin(x) = Primitive.zr_math_call_fast(2, x) || Primitive.zr_math_call(2, check(x), 0.0)
  def cos(x) = Primitive.zr_math_call_fast(3, x) || Primitive.zr_math_call(3, check(x), 0.0)
  def tan(x) = Primitive.zr_math_call_fast(4, x) || Primitive.zr_math_call(4, check(x), 0.0)
  def atan(x) = Primitive.zr_math_call_fast(5, x) || Primitive.zr_math_call(5, check(x), 0.0)
  def exp(x) = Primitive.zr_math_call_fast(6, x) || Primitive.zr_math_call(6, check(x), 0.0)
  def atan2(y, x) = Primitive.zr_math_call(7, check(y), check(x))
  def hypot(x, y) = Primitive.zr_math_call(8, check(x), check(y))
  def sinh(x) = Primitive.zr_math_call(9, check(x), 0.0)
  def cosh(x) = Primitive.zr_math_call(10, check(x), 0.0)
  def tanh(x) = Primitive.zr_math_call(11, check(x), 0.0)
  def expm1(x) = Primitive.zr_math_call(24, check(x), 0.0)

  def log1p(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - log1p" if x < -1.0

    Primitive.zr_math_call(25, x, 0.0)
  end

  def log(x, base = nil)
    x, bits = split(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - log" if x < 0.0

    value = Primitive.zr_math_call(12, x, 0.0) + bits * 0.6931471805599453
    return value if base.nil?

    base = check(base)
    raise DomainError, +"Numerical argument is out of domain - log" if base < 0.0

    value / Primitive.zr_math_call(12, base, 0.0)
  end

  def log2(x)
    x, bits = split(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - log2" if x < 0.0

    Primitive.zr_math_call(13, x, 0.0) + bits
  end

  def log10(x)
    x, bits = split(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - log10" if x < 0.0

    Primitive.zr_math_call(14, x, 0.0) + bits * 0.3010299956639812
  end

  def asin(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - asin" if x < -1.0 || x > 1.0

    Primitive.zr_math_call(15, x, 0.0)
  end

  def acos(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - acos" if x < -1.0 || x > 1.0

    Primitive.zr_math_call(16, x, 0.0)
  end

  def asinh(x) = Primitive.zr_math_call(17, check(x), 0.0)

  def acosh(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - acosh" if x < 1.0

    Primitive.zr_math_call(18, x, 0.0)
  end

  def atanh(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - atanh" if x < -1.0 || x > 1.0

    Primitive.zr_math_call(19, x, 0.0)
  end

  # Gamma is exact at the small positive integers, and refused at zero's
  # negative side and the negative integers.
  def gamma(x)
    x = check(x)
    if x.infinite? && x < 0 || (x < 0 && x.finite? && x == x.floor) || (x == 0 && 1.0 / x < 0)
      raise DomainError, +"Numerical argument is out of domain - gamma"
    end
    return FACTORIALS[x.to_i - 1] if x == x.floor && x >= 1 && x <= FACTORIALS.size

    Primitive.zr_math_call(20, x, 0.0)
  end

  # (n - 1)! for n from 1 to 23: gamma's exact answers.
  FACTORIALS = (0..22).map { |n| (1..n).reduce(1.0) { |m, i| m * i } }.freeze
  private_constant :FACTORIALS

  def lgamma(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - lgamma" if x.infinite? && x < 0
    return [Float::INFINITY, 1.0 / x < 0 ? -1 : 1] if x == 0
    return [Float::INFINITY, 1] if x.infinite? || (x < 0 && x == x.floor)

    Primitive.zr_math_lgamma(x)
  end

  def erf(x) = Primitive.zr_math_call(21, check(x), 0.0)

  def erfc(x) = Primitive.zr_math_call(22, check(x), 0.0)

  def frexp(x)
    x = check(x)
    return [x, 0] if x.nan? || x.infinite?

    Primitive.zr_math_frexp(x)
  end

  def ldexp(fraction, exponent)
    fraction = check(fraction)
    exponent = Numeric.send(:int_operand, exponent)
    Primitive.zr_math_call(23, fraction, exponent)
  end

  # rb_to_float: a Float as it is, any other Numeric through to_f, and
  # nothing else, whatever answers to_f.
  def check(x)
    Primitive.attr! :hidden
    return x if Primitive.zr_float_p_m(x)
    return x.to_f if Primitive.zr_integer_p_m(x)
    raise TypeError, "can't convert #{x.nil? ? "nil" : x.class} into Float" unless x.is_a?(Numeric)

    x.to_f
  end

  # A bignum too wide for a double logs through its top bits: the
  # rest is a count of doublings.
  def split(x)
    Primitive.attr! :hidden
    return [x, 0] unless x.is_a?(Integer) && x > 0 && x.bit_length >= 1024

    bits = x.bit_length - 53
    [x >> bits, bits]
  end
end

class Float
  # `half:` decides a tie: :up (the default), :even, or :down. A tie is
  # a scaled value whose fraction is exactly one half in the double.
  def round(digits = 0, half: nil)
    digits = Numeric.send(:int_operand, digits)
    mode = Numeric.send(:half_mode, half)
    if digits != 0 && finite? && !zero?
      # CRuby's float_round_overflow and float_round_underflow, with C's
      # truncating division: past these the scaled value is whole
      # already, or rounds to zero.
      binexp = Primitive.zr_math_frexp(self)[1]
      return self if digits > 0 && digits >= 17 - (binexp > 0 ? binexp / 4 : -(-binexp / 3) - 1)
      return digits > 0 ? 0.0 : 0 if digits < -(binexp > 0 ? binexp / 3 + 1 : -(-binexp / 4))
    end
    plain = Primitive.zr_flo_round_m(self, digits)
    return exactly(digits, :round, half: mode) if plain.nil?
    return plain if mode == :up || !finite?

    scaled = digits > 0 ? self * 10.0**digits : (digits < 0 ? self / 10.0**-digits : self)
    return plain unless scaled.finite? && scaled - scaled.floor == 0.5

    base = scaled.floor
    n = mode == :down ? (self > 0 ? base : base + 1) : (base.even? ? base : base + 1)
    digits > 0 ? n / 10.0**digits : (digits < 0 ? n * 10**-digits : n)
  end

  # Past DBL_DIG places the power of ten the scaling wants is not
  # exact, so ruby works from the exact value the double holds. The
  # kernel answers nil to ask for this.
  def exactly(digits, verb, **options)
    Primitive.attr! :hidden
    scale = Rational(10)**digits
    ((to_r * scale).public_send(verb, **options) / scale).to_f
  end
end
