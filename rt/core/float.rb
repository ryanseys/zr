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
  def integer? = false
  def zero? = self == 0.0
  def positive? = self > 0.0
  def negative? = self < 0.0
  # A negative count of digits rounds the Integer the value becomes.
  def floor(digits = 0)
    digits = Primitive.zr_index_operand_m(digits)
    digits < 0 ? __floor__.floor(digits) : __floor__(digits)
  end

  def ceil(digits = 0)
    digits = Primitive.zr_index_operand_m(digits)
    digits < 0 ? __ceil__.ceil(digits) : __ceil__(digits)
  end

  def truncate(digits = 0) = self > 0 ? floor(digits) : ceil(digits)
  def fdiv(other) = self / other
  def quo(other) = self / other

  # The quotient and the modulo, as CRuby's flodivmod pairs them.
  def divmod(other)
    other = other.to_f if other.is_a?(Integer)
    raise TypeError, "#{other.class} can't be coerced into Float" unless other.is_a?(Float)
    raise ZeroDivisionError, "divided by 0" if other == 0.0

    [Primitive.zr_float_quotient_value(self, other).to_i, self % other]
  end

  def div(other)
    other = other.to_f if other.is_a?(Integer)
    raise ZeroDivisionError, "divided by 0" if other == 0.0

    (self / other).floor
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
  def Float(value, exception: true)
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

      raise TypeError, "can't convert #{value.class} into Float"
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

  def self.sqrt(x)
    x = check(x, "sqrt")
    raise DomainError, "Numerical argument is out of domain - sqrt" if x < 0.0
    return 0.0 if x == 0.0

    Primitive.zr_math_sqrt(x)
  end

  def self.cbrt(x) = Primitive.zr_math_call(1, check(x, "cbrt"), 0.0)
  def self.sin(x) = Primitive.zr_math_call(2, check(x, "sin"), 0.0)
  def self.cos(x) = Primitive.zr_math_call(3, check(x, "cos"), 0.0)
  def self.tan(x) = Primitive.zr_math_call(4, check(x, "tan"), 0.0)
  def self.atan(x) = Primitive.zr_math_call(5, check(x, "atan"), 0.0)
  def self.exp(x) = Primitive.zr_math_call(6, check(x, "exp"), 0.0)
  def self.atan2(y, x) = Primitive.zr_math_call(7, check(y, "atan2"), check(x, "atan2"))
  def self.hypot(x, y) = Primitive.zr_math_call(8, check(x, "hypot"), check(y, "hypot"))
  def self.sinh(x) = Primitive.zr_math_call(9, check(x, "sinh"), 0.0)
  def self.cosh(x) = Primitive.zr_math_call(10, check(x, "cosh"), 0.0)
  def self.tanh(x) = Primitive.zr_math_call(11, check(x, "tanh"), 0.0)
  def self.expm1(x) = Primitive.zr_math_call(24, check(x, "expm1"), 0.0)

  def self.log1p(x)
    x = check(x, "log1p")
    raise DomainError, "Numerical argument is out of domain - log1p" if x < -1.0

    Primitive.zr_math_call(25, x, 0.0)
  end

  def self.log(x, base = nil)
    x, bits = split(x)
    x = check(x, "log")
    raise DomainError, "Numerical argument is out of domain - log" if x < 0.0

    value = Primitive.zr_math_call(12, x, 0.0) + bits * 0.6931471805599453
    return value if base.nil?

    base = check(base, "log")
    raise DomainError, "Numerical argument is out of domain - log" if base < 0.0

    value / Primitive.zr_math_call(12, base, 0.0)
  end

  def self.log2(x)
    x, bits = split(x)
    x = check(x, "log2")
    raise DomainError, "Numerical argument is out of domain - log2" if x < 0.0

    Primitive.zr_math_call(13, x, 0.0) + bits
  end

  def self.log10(x)
    x, bits = split(x)
    x = check(x, "log10")
    raise DomainError, "Numerical argument is out of domain - log10" if x < 0.0

    Primitive.zr_math_call(14, x, 0.0) + bits * 0.3010299956639812
  end

  def self.asin(x)
    x = check(x, "asin")
    raise DomainError, "Numerical argument is out of domain - asin" if x < -1.0 || x > 1.0

    Primitive.zr_math_call(15, x, 0.0)
  end

  def self.acos(x)
    x = check(x, "acos")
    raise DomainError, "Numerical argument is out of domain - acos" if x < -1.0 || x > 1.0

    Primitive.zr_math_call(16, x, 0.0)
  end

  def self.asinh(x) = Primitive.zr_math_call(17, check(x, "asinh"), 0.0)

  def self.acosh(x)
    x = check(x, "acosh")
    raise DomainError, "Numerical argument is out of domain - acosh" if x < 1.0

    Primitive.zr_math_call(18, x, 0.0)
  end

  def self.atanh(x)
    x = check(x, "atanh")
    raise DomainError, "Numerical argument is out of domain - atanh" if x < -1.0 || x > 1.0

    Primitive.zr_math_call(19, x, 0.0)
  end

  # Gamma is exact at the small positive integers, and refused at zero's
  # negative side and the negative integers.
  def self.gamma(x)
    x = check(x, "gamma")
    if x.infinite? && x < 0 || (x < 0 && x.finite? && x == x.floor) || (x == 0 && 1.0 / x < 0)
      raise DomainError, "Numerical argument is out of domain - gamma"
    end
    return FACTORIALS[x.to_i - 1] if x == x.floor && x >= 1 && x <= FACTORIALS.size

    Primitive.zr_math_call(20, x, 0.0)
  end

  # (n - 1)! for n from 1 to 23: gamma's exact answers.
  FACTORIALS = (0..22).map { |n| (1..n).reduce(1.0) { |m, i| m * i } }.freeze
  private_constant :FACTORIALS

  def self.lgamma(x)
    x = check(x, "lgamma")
    raise DomainError, "Numerical argument is out of domain - lgamma" if x.infinite? && x < 0
    return [Float::INFINITY, 1] if x.infinite? || (x < 0 && x == x.floor) || x == 0

    Primitive.zr_math_lgamma(x)
  end

  def self.erf(x) = Primitive.zr_math_call(21, check(x, "erf"), 0.0)

  def self.erfc(x) = Primitive.zr_math_call(22, check(x, "erfc"), 0.0)

  def self.frexp(x)
    x = check(x, "frexp")
    return [x, 0] if x.nan? || x.infinite?

    Primitive.zr_math_frexp(x)
  end

  def self.ldexp(fraction, exponent)
    fraction = check(fraction, "ldexp")
    exponent = Primitive.zr_index_operand_m(exponent)
    exponent = exponent.clamp(-100_000, 100_000)
    Primitive.zr_math_call(23, fraction, exponent)
  end

  def self.check(x, name)
    Primitive.attr! :hidden
    return x.to_f if x.is_a?(Integer)
    return x if x.is_a?(Float)
    raise TypeError, "can't convert #{x.nil? ? "nil" : x.class} into Float" if x.nil? || x.is_a?(String) || !x.respond_to?(:to_f)

    x.to_f
  end
  private_class_method :check

  # A bignum too wide for a double logs through its top bits: the
  # rest is a count of doublings.
  def self.split(x)
    Primitive.attr! :hidden
    return [x, 0] unless x.is_a?(Integer) && x > 0 && x.bit_length >= 1024

    bits = x.bit_length - 53
    [x >> bits, bits]
  end
  private_class_method :split

  # The functions read as bare names too, as `include Math` gives them.
  singleton_methods(false).each do |name|
    define_method(name) { |*args| Math.send(name, *args) }
    private name
  end
end

class Float
  # `half:` decides a tie: :up (the default), :even, or :down. A tie is
  # a scaled value whose fraction is exactly one half in the double.
  def round(digits = 0, half: nil)
    digits = Primitive.zr_index_operand_m(digits)
    mode = Numeric.send(:half_mode, half)
    return __round__(digits) if mode == :up || !finite?

    scaled = digits > 0 ? self * 10.0**digits : (digits < 0 ? self / 10.0**-digits : self)
    return __round__(digits) unless scaled.finite? && scaled - scaled.floor == 0.5

    base = scaled.floor
    n = mode == :down ? (self > 0 ? base : base + 1) : (base.even? ? base : base + 1)
    digits > 0 ? n / 10.0**digits : (digits < 0 ? n * 10**-digits : n)
  end

  # A number is its own copy.
  def dup = self

  def clone(freeze: nil)
    raise ArgumentError, "can't unfreeze Float" if freeze == false

    self
  end
end
