# Float: the constants, and the methods written over the kernel's
# arithmetic.
class Float
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
  def truncate(digits = 0) = digits > 0 ? Primitive.zr_unimplemented("Float#truncate with digits") : to_i
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

  def coerce(other)
    return [other, self] if other.is_a?(Float)
    return [other.to_f, self] if other.is_a?(Integer)

    raise TypeError, "#{other.class} can't be coerced into Float"
  end

  def rationalize(*args) = Primitive.zr_unimplemented("Float#rationalize")
  def to_r = Primitive.zr_unimplemented("Float#to_r")
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
    when nil
      return nil unless exception

      raise TypeError, "can't convert nil into Float"
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

  def self.log(x, base = nil)
    x = check(x, "log")
    raise DomainError, "Numerical argument is out of domain - log" if x < 0.0
    return Primitive.zr_math_call(12, x, 0.0) if base.nil?

    Primitive.zr_math_call(12, x, 0.0) / Primitive.zr_math_call(12, check(base, "log"), 0.0)
  end

  def self.log2(x)
    x = check(x, "log2")
    raise DomainError, "Numerical argument is out of domain - log2" if x < 0.0

    Primitive.zr_math_call(13, x, 0.0)
  end

  def self.log10(x)
    x = check(x, "log10")
    raise DomainError, "Numerical argument is out of domain - log10" if x < 0.0

    Primitive.zr_math_call(14, x, 0.0)
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

  def self.check(x, name)
    Primitive.attr! :hidden
    return x.to_f if x.is_a?(Integer)
    return x if x.is_a?(Float)
    raise TypeError, "can't convert #{x.nil? ? "nil" : x.class} into Float" if x.nil? || x.is_a?(String) || !x.respond_to?(:to_f)

    x.to_f
  end
  private_class_method :check
end
