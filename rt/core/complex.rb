# Complex: a real and an imaginary part, each an Integer, Float or
# Rational, held in hidden ivars as CRuby's hidden fields are.
class Complex < Numeric
  class << self
    undef_method :new

    def build(real, imag)
      Primitive.attr! :hidden
      c = allocate
      Primitive.zr_hidden_set(c, :__real__, real)
      Primitive.zr_hidden_set(c, :__imag__, imag)
      c.freeze
    end
    private :build

    def rectangular(real, imag = 0)
      raise TypeError, "not a real" unless real.is_a?(Numeric) && real.real? && imag.is_a?(Numeric) && imag.real?

      build(real, imag)
    end

    alias rect rectangular

    # CRuby's f_complex_polar: the exact quarter turns stay exact.
    def polar(radius, theta = 0)
      raise TypeError, "not a real" unless radius.is_a?(Numeric) && radius.real? && theta.is_a?(Numeric) && theta.real?
      return build(radius, 0.0) if radius == 0 || theta == 0

      if theta.is_a?(Float)
        return build(-radius, 0.0) if theta == Math::PI
        return build(0.0, radius) if theta == Math::PI / 2
        return build(0.0, -radius) if theta == -Math::PI / 2
      end
      build(radius * Math.cos(theta), radius * Math.sin(theta))
    end

    # A value of any numeric kind as a Complex, as Kernel#Complex reads
    # it; nil when `exception` is false and it cannot be.
    def convert(value, exception)
      Primitive.attr! :hidden
      case value
      when Complex then value
      when Integer, Float, Rational then build(value, 0)
      when String then parse(value, exception)
      when nil
        return nil unless exception

        raise TypeError, "can't convert nil into Complex"
      else
        if value.respond_to?(:to_c)
          value.to_c
        else
          return nil unless exception

          raise TypeError, "can't convert #{value.class} into Complex"
        end
      end
    end
    private :convert

    # A real number's text, as a pattern piece (a String, so the core
    # loads without the regexp engine).
    NUMBER = "[-+]?(?:\\d+(?:_\\d+)*(?:\\.\\d+(?:_\\d+)*)?(?:[eE][-+]?\\d+)?(?:\\/\\d+(?:_\\d+)*)?)"
    private_constant :NUMBER

    # The forms a Complex is written in, compiled on first use (a
    # constant would ask the engine at boot).
    def forms
      Primitive.attr! :hidden
      @forms ||= {
        polar: Regexp.new("\\A(#{NUMBER})@(#{NUMBER})\\z"),
        pair: Regexp.new("\\A(#{NUMBER})?([-+])?(#{NUMBER})?i\\z"),
        imaginary: Regexp.new("\\A(#{NUMBER})i\\z"),
        real: Regexp.new("\\A(#{NUMBER})\\z"),
        leading: Regexp.new("\\A\\s*(?:#{NUMBER}@#{NUMBER}|#{NUMBER}?[-+]#{NUMBER}?i|#{NUMBER}i|[-+]?i|#{NUMBER})")
      }
    end
    private :forms

    # "1+2i", "3i", "-i", "2.5", "1/2+3/4i", "1@2" (polar).
    def parse(text, exception)
      Primitive.attr! :hidden
      body = text.strip
      if (m = forms[:polar].match(body))
        return polar(real_part(m[1]), real_part(m[2]))
      end
      if (m = forms[:pair].match(body)) && (m[2] || m[1].nil?) && !(m[1].nil? && m[2].nil? && m[3].nil? && body != "i")
        real = m[1] ? real_part(m[1]) : 0
        imag = m[3] ? real_part(m[3]) : 1
        imag = -imag if m[2] == "-"
        return build(real, imag)
      end
      if (m = forms[:imaginary].match(body))
        return build(0, real_part(m[1]))
      end
      if (m = forms[:real].match(body))
        return build(real_part(m[1]), 0)
      end
      return nil unless exception

      raise ArgumentError, "invalid value for convert(): #{text.inspect}"
    end
    private :parse

    def leading(text)
      Primitive.attr! :hidden
      m = forms[:leading].match(text)
      m && m[0]
    end
    private :leading

    def real_part(digits)
      Primitive.attr! :hidden
      return Rational.send(:parse, digits, true) if digits.include?("/")
      return digits.delete("_").to_f if digits.include?(".") || digits =~ /[eE]/

      digits.delete("_").to_i
    end
    private :real_part
  end

  I = build(0, 1)

  # Complex is not ordered, and has no integer parts.
  %i[< <= > >= between? clamp % div divmod floor ceil modulo remainder round step truncate i positive? negative?].each do |name|
    undef_method(name) if method_defined?(name)
  end

  def real = Primitive.zr_hidden_get(self, :__real__)

  def imaginary = Primitive.zr_hidden_get(self, :__imag__)

  alias imag imaginary

  def real? = false

  def rectangular = [real, imaginary]

  alias rect rectangular

  # Exact along an axis, as CRuby keeps it: a Float on the other axis
  # only makes the answer a Float.
  def abs
    if real == 0
      a = imaginary.abs
      return real.is_a?(Float) && !imaginary.is_a?(Float) ? a.to_f : a
    end
    if imaginary == 0
      a = real.abs
      return imaginary.is_a?(Float) && !real.is_a?(Float) ? a.to_f : a
    end
    Math.hypot(real, imaginary)
  end

  alias magnitude abs

  def abs2 = real * real + imaginary * imaginary

  def arg = Math.atan2(imaginary, real)

  alias angle arg
  alias phase arg

  def polar = [abs, arg]

  def conjugate = Complex.send(:build, real, -imaginary)

  alias conj conjugate

  def -@ = Complex.send(:build, -real, -imaginary)

  def +(other)
    case other
    when Complex then Complex.send(:build, real + other.real, imaginary + other.imaginary)
    when Integer, Float, Rational then Complex.send(:build, real + other, imaginary)
    else Primitive.zr_num_coerce_m(self, other, :+, 0)
    end
  end

  def -(other)
    case other
    when Complex then Complex.send(:build, real - other.real, imaginary - other.imaginary)
    when Integer, Float, Rational then Complex.send(:build, real - other, imaginary)
    else Primitive.zr_num_coerce_m(self, other, :-, 0)
    end
  end

  def *(other)
    case other
    when Complex
      Complex.send(:build, real * other.real - imaginary * other.imaginary, real * other.imaginary + imaginary * other.real)
    when Integer, Float, Rational then Complex.send(:build, real * other, imaginary * other)
    else Primitive.zr_num_coerce_m(self, other, :*, 0)
    end
  end

  # CRuby's f_divide with quo: scaled by the larger component of the
  # divisor, exact parts canonicalized back to Integers.
  def /(other)
    case other
    when Complex
      floating = [real, imaginary, other.real, other.imaginary].any? { |x| x.is_a?(Float) }
      if other.real.abs > other.imaginary.abs
        r = other.imaginary.quo(other.real)
        n = other.real * (1 + r * r)
        x = (real + imaginary * r).quo(n)
        y = (imaginary - real * r).quo(n)
      else
        r = other.real.quo(other.imaginary)
        n = other.imaginary * (1 + r * r)
        x = (real * r + imaginary).quo(n)
        y = (imaginary * r - real).quo(n)
      end
      Complex.send(:build, floating ? x : canonical(x), floating ? y : canonical(y))
    when Integer, Float, Rational
      Complex.send(:build, canonical(real.quo(other)), canonical(imaginary.quo(other)))
    else Primitive.zr_num_coerce_m(self, other, :/, 0)
    end
  end

  alias quo /

  def fdiv(other) = Complex.send(:build, real.to_f / other, imaginary.to_f / other)

  def **(other)
    other = other.real if other.is_a?(Complex) && other.imaginary == 0 && !other.imaginary.is_a?(Float)
    other = other.numerator if other.is_a?(Rational) && other.denominator == 1
    case other
    when Integer
      return Complex.send(:build, 1, 0) if other == 0

      base = other > 0 ? self : Complex.send(:build, 1, 0) / self
      n = other.abs
      result = nil
      while n > 0
        result = result.nil? ? base : result * base if n.odd?
        n >>= 1
        base *= base if n > 0
      end
      result
    when Float, Rational
      return Complex.send(:build, 1, 0) if other == 0 && !other.is_a?(Float)

      radius, theta = polar
      Complex.polar(radius**other, theta * other)
    when Complex
      radius, theta = polar
      ore, oim = other.real, other.imaginary
      log = Math.log(radius)
      r = Math.exp(ore * log - oim * theta)
      t = theta * ore + oim * log
      Complex.polar(r, t)
    else Primitive.zr_num_coerce_m(self, other, :**, 0)
    end
  end

  def ==(other)
    case other
    when Complex then real == other.real && imaginary == other.imaginary
    when Integer, Float, Rational then real == other && imaginary == 0
    else other == self
    end
  end

  def <=>(other)
    return nil unless imaginary == 0 && !imaginary.is_a?(Float) || (imaginary.is_a?(Float) && imaginary == 0)

    case other
    when Complex then other.imaginary == 0 ? real <=> other.real : nil
    when Integer, Float, Rational then real <=> other
    end
  end

  def eql?(other) = other.is_a?(Complex) && real.eql?(other.real) && imaginary.eql?(other.imaginary)

  def hash = [real, imaginary, :Complex].hash

  def coerce(other)
    case other
    when Complex then [other, self]
    when Integer, Float, Rational then [Complex.send(:build, other, 0), self]
    else raise TypeError, "#{other.class} can't be coerced into Complex"
    end
  end

  # Over the common denominator of both parts.
  def denominator = real.denominator.lcm(imaginary.denominator)

  def numerator
    d = denominator
    Complex.send(:build, real.numerator * (d / real.denominator), imaginary.numerator * (d / imaginary.denominator))
  end

  def finite? = !(real.is_a?(Float) && !real.finite?) && !(imaginary.is_a?(Float) && !imaginary.finite?)

  def infinite? = finite? ? nil : 1

  def to_c = self

  def to_i
    raise RangeError, "can't convert #{self} into Integer" unless exact_real?

    real.to_i
  end

  def to_f
    raise RangeError, "can't convert #{self} into Float" unless exact_real?

    real.to_f
  end

  def to_r
    raise RangeError, "can't convert #{self} into Rational" unless exact_real?

    real.to_r
  end

  def rationalize(eps = nil)
    raise RangeError, "can't convert #{self} into Rational" unless exact_real?

    real.rationalize(eps)
  end

  def to_s
    text = +""
    text << part_text(real)
    positive = imaginary.is_a?(Float) ? !(imaginary < 0 || (imaginary == 0 && 1.0 / imaginary < 0)) && !imaginary.nan? || imaginary.nan? : imaginary >= 0
    text << (positive ? "+" : "-")
    imag_text = part_text(imaginary.is_a?(Float) && imaginary.nan? ? imaginary : imaginary.abs)
    text << imag_text
    text << "*" unless imag_text[-1].match?(/\d/)
    text << "i"
  end

  def inspect = "(#{self})"

  private

  def part_text(x)
    return "(#{x})" if x.is_a?(Rational)

    x.to_s
  end

  def exact_real?
    !imaginary.is_a?(Float) && imaginary == 0
  end

  # A Rational that is whole becomes its Integer.
  def canonical(x)
    x.is_a?(Rational) && x.denominator == 1 ? x.numerator : x
  end
end

module Kernel
  def Complex(real, imag = nil, exception: true)
    if imag.nil?
      Complex.send(:convert, real, exception)
    elsif real.is_a?(Numeric) && real.real? && imag.is_a?(Numeric) && imag.real?
      Complex.send(:build, real, imag)
    else
      x = Complex.send(:convert, real, exception)
      y = Complex.send(:convert, imag, exception)
      return nil if x.nil? || y.nil?

      Complex.send(:build, x.real - y.imaginary, x.imaginary + y.real)
    end
  end
  private :Complex
  module_function :Complex
end

class Numeric
  def real? = true

  def real = self

  def imaginary = 0

  alias imag imaginary

  def rectangular = [self, 0]

  alias rect rectangular

  def conjugate = self

  alias conj conjugate

  def abs2 = self * self

  def arg = negative? ? Math::PI : 0

  alias angle arg
  alias phase arg

  def polar = [abs, arg]

  def i = Complex.send(:build, 0, self)

  def to_c = Complex.send(:build, self, 0)

  # A number's singleton is refused, as every Numeric is a value.
  def singleton_method_added(name)
    singleton_class.send(:remove_method, name)
    raise TypeError, "can't define singleton method \"#{name}\" for #{self.class}"
  end
end

class Complex
  undef_method :i
end

class Float
  def arg = nan? ? self : (negative? || (zero? && 1.0 / self < 0) ? Math::PI : 0)

  alias angle arg
  alias phase arg
end

class String
  # The longest leading text that reads as a Complex; 0 when none does.
  def to_c
    head = Complex.send(:leading, self)
    (head && Complex.send(:parse, head, false)) || Complex.send(:build, 0, 0)
  end
end

class NilClass
  def to_c = Complex.send(:build, 0, 0)
end

class Complex
  def marshal_dump = [real, imaginary]

  def marshal_load(pair)
    Primitive.zr_hidden_set(self, :__real__, pair[0])
    Primitive.zr_hidden_set(self, :__imag__, pair[1])
    freeze
  end

  private :marshal_dump, :marshal_load
end
