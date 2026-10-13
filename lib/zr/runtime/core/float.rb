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

  # flo_quo: `/` under a guard, as num_funcall1 sends it, so a `/` that
  # comes back here (`alias / quo`) raises NameError and no
  # SystemStackError.
  def quo(other)
    raise NameError.new("#{self}/#{other}", :/) if Primitive.zr_recursive_enter_paired(self, other, :quo)

    begin
      # A program's `/` runs, as num_funcall1 sends it; the core's own
      # `__send__` would call the core's `/`.
      public_send(:/, other)
    ensure
      Primitive.zr_recursive_leave(self, :quo)
    end
  end

  # The quotient and the modulo, as CRuby's flodivmod pairs them. An
  # unknown operand coerces, as flo_divmod passes it on.
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
    exception = exception_flag(exception)
    value = arg
    case value
    when Float then value
    when Integer then value.to_f
    when String
      # rb_str_to_dbl: ASCII text with no NUL in it.
      encoding = Encoding.at(Primitive.zr_str_encoding_index_m(value))
      raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{encoding}" unless encoding.ascii_compatible?
      if String.instance_method(:include?).bind_call(value, "\0")
        return nil unless exception

        raise ArgumentError, +"string for Float contains null byte"
      end

      result = Primitive.zr_str_to_f_strict(value)
      return result if result || !exception

      raise ArgumentError, "invalid value for Float(): #{value.inspect}"
    when nil, true, false
      return nil unless exception

      raise TypeError, cant_convert(value, "Float")
    else
      # rb_convert_to_float: to_f must give a Float; with exception: false,
      # an error in it gives nil.
      unless exception
        converted = Primitive.zr_protect(nil) { value.to_f if value.respond_to?(:to_f) }
        return converted.is_a?(Float) ? converted : nil
      end
      raise TypeError, cant_convert(value, "Float") unless value.respond_to?(:to_f)

      converted = value.to_f
      return converted if converted.is_a?(Float)

      raise TypeError, cant_convert_gives(value, "Float", :to_f, converted)
    end
  end

  private :Float
  module_function :Float
end

class String
  # rb_str_to_dbl: the text must be ASCII-compatible.
  def to_f
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{enc}" unless enc.ascii_compatible?

    Primitive.zr_str_to_f(self)
  end
end

# The libm functions, over doubles; an Integer argument converts.
module Math
  PI = 3.141592653589793
  E = 2.718281828459045

  # The doublings that a wide Bignum's logarithm counts convert as C
  # doubles do, never through a program's Integer#to_f.
  INT_TO_F = Integer.instance_method(:to_f)
  private_constant :INT_TO_F

  # Each function is a private method too, for `include Math`.
  module_function

  # The kernel returns immediately for a Float or an Integer in the
  # domain (zr_math_sqrt_fast). Any other value goes through the full
  # conversion, which converts or refuses it.
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

  # rb_math_log, as clang builds it on arm64: the doublings of a wide
  # Bignum join through a fused multiply-add, and a base divides the
  # base-2 logarithms. The difference of the two counts of doublings is
  # a size_t, so it wraps when the base is the wider one.
  def log(x, base = (plain = true; nil))
    x, bits = split(x)
    x = check(x)
    raise DomainError, +"Numerical argument is out of domain - log" if x < 0.0

    if plain
      return -Float::INFINITY if x == 0.0

      return Primitive.zr_math_fma(INT_TO_F.bind_call(bits), 0.6931471805599453, Primitive.zr_math_call(12, x, 0.0))
    end

    base, base_bits = split(base)
    base = check(base)
    raise DomainError, +"Numerical argument is out of domain - log" if base < 0.0
    return base == 0.0 ? Float::NAN : -Float::INFINITY if x == 0.0
    return -0.0 if base == 0.0

    log2_base = Primitive.zr_math_call(13, base, 0.0)
    wide = bits - base_bits
    wide += 1 << 64 if wide < 0
    (Primitive.zr_math_call(13, x, 0.0) / log2_base) + (INT_TO_F.bind_call(wide) / log2_base)
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
  # math_gamma: an infinity and a zero of either sign are poles, and only
  # the negative whole numbers are out of the domain.
  def gamma(x)
    x = check(x)
    if x.infinite?
      raise DomainError, +"Numerical argument is out of domain - gamma" if x < 0

      return Float::INFINITY
    end
    return 1.0 / x < 0 ? -Float::INFINITY : Float::INFINITY if x == 0.0
    raise DomainError, +"Numerical argument is out of domain - gamma" if x < 0 && x == x.floor
    return FACTORIALS[x.to_i - 1] if x >= 1 && x <= FACTORIALS.size && x == x.floor

    Primitive.zr_math_call(20, x, 0.0)
  end

  # (n - 1)! for n from 1 to 23: gamma's exact results.
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
  # nothing else, even if it responds to to_f.
  def check(x)
    Primitive.attr! :hidden
    return x if Primitive.zr_float_p_m(x)
    return x.to_f if Primitive.zr_integer_p_m(x)
    raise TypeError, cant_convert(x, "Float") unless x.is_a?(Numeric)

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
    # flo_round: zero keeps its sign past the point; a negative count
    # rounds the truncated Integer.
    return digits > 0 ? self : 0 if zero?
    return to_i.round(digits, half: mode) if digits < 0

    plain = Primitive.zr_flo_round_m(self, digits)
    return exactly(digits, :round, half: mode) if plain.nil?
    return plain if mode == :up || !finite?

    if digits > 0
      s = 10.0**digits
      return (mode == :even ? half_even(self, s) : half_down(self, s)) / s
    end

    scaled = self
    return plain unless scaled - scaled.floor == 0.5

    base = scaled.floor
    mode == :down ? (self > 0 ? base : base + 1) : (base.even? ? base : base + 1)
  end

  # numeric.c's round_half_down and round_half_even: `x` scaled by `s`,
  # rounded, and checked against `x` once more after the division.
  def half_down(x, s)
    Primitive.attr! :hidden
    f = (x * s).round.to_f
    if x > 0
      f -= 1 if (f - 0.5) / s >= x
    elsif (f + 0.5) / s <= x
      f += 1
    end
    f
  end

  def half_even(x, s)
    Primitive.attr! :hidden
    u = x.truncate.to_f
    us = u * s
    vs = (x - u) * s
    if x > 0.0
      f = vs.floor.to_f
      uf = us + f
      d = vs - f
      d = if d > 0.5 then 1.0
          elsif d == 0.5 || (uf + 0.5) / s <= x then uf.remainder(2.0)
          else 0.0
          end
      us + f + d
    else
      f = vs.ceil.to_f
      uf = us + f
      d = f - vs
      d = if d > 0.5 then 1.0
          elsif d == 0.5 || (uf - 0.5) / s >= x then (-uf).remainder(2.0)
          else 0.0
          end
      us + f - d
    end
  end

  # Past DBL_DIG places the power of ten that the scaling needs is not
  # exact, so ruby works from the exact value of the double. The kernel
  # returns nil to request this.
  def exactly(digits, verb, **options)
    Primitive.attr! :hidden
    scale = Rational(10)**digits
    ((to_r * scale).public_send(verb, **options) / scale).to_f
  end
end
