# frozen_string_literal: true

# Complex: a real and an imaginary part, each an Integer, Float or
# Rational, kept in hidden ivars as in CRuby's hidden fields.
class Complex < Numeric
  class << self
    undef_method :new, :allocate

    def build(real, imag)
      Primitive.attr! :hidden
      c = Primitive.zr_class_build(self)
      Primitive.zr_hidden_set(c, :__real__, real)
      Primitive.zr_hidden_set(c, :__imag__, imag)
      c.freeze
    end
    private :build

    # safe_mul: a finite Float times an exact or Float zero is that zero
    # with the Float's sign, as is an infinite one.
    def safe_mul(a, b, az, bz)
      Primitive.attr! :hidden
      a = a.negative? || (a.zero? && 1.0 / a < 0) ? -1.0 : 1.0 if !az && bz && a.is_a?(Float) && !a.nan?
      b = b.negative? || (b.zero? && 1.0 / b < 0) ? -1.0 : 1.0 if !bz && az && b.is_a?(Float) && !b.nan?
      a * b
    end
    private :safe_mul

    # nucomp_real_check: a real number, or a Complex whose imaginary part
    # is zero, as its real part. Else "not a real".
    def real_part_of(num)
      Primitive.attr! :hidden
      return num.real if num.is_a?(Complex) && num.imaginary.zero?
      raise TypeError, +"not a real" unless num.is_a?(Numeric) && num.real?

      num
    end
    private :real_part_of

    def rectangular(real, imag = 0)
      build(real_part_of(real), real_part_of(imag))
    end

    alias rect rectangular

    # CRuby's f_complex_polar: the exact quarter turns stay exact.
    def polar(radius, theta = 0)
      radius = real_part_of(radius)
      theta = real_part_of(theta)
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
      # nucomp_convert: a Numeric that is not real is already complex.
      when Numeric
        return value unless value.real?

        value.to_c
      when nil
        return nil unless exception

        raise TypeError, +"can't convert nil into Complex"
      else
        if value.respond_to?(:to_c)
          value.to_c
        else
          return nil unless exception

          raise TypeError, "can't convert #{conversion_name(value)} into Complex"
        end
      end
    end
    private :convert

    # A real number's text, as a pattern piece (a String, so the core
    # loads without the regexp engine).
    NUMBER = "[-+]?(?:\\d+(?:_\\d+)*(?:\\.\\d+(?:_\\d+)*)?(?:[eE][-+]?\\d+)?(?:\\/\\d+(?:_\\d+)*)?)"
    private_constant :NUMBER

    # The forms in which a Complex is written (the imaginary unit is any
    # of i, I, j and J, as read_comp takes it), compiled on first use (a
    # constant would call the engine at boot).
    def forms
      Primitive.attr! :hidden
      @forms ||= {
        polar: Regexp.new("\\A(#{NUMBER})@(#{NUMBER})\\z"),
        pair: Regexp.new("\\A(#{NUMBER})?([-+])?(#{NUMBER})?[iIjJ]\\z"),
        imaginary: Regexp.new("\\A(#{NUMBER})[iIjJ]\\z"),
        real: Regexp.new("\\A(#{NUMBER})\\z"),
        leading: Regexp.new("\\A\\s*(?:#{NUMBER}@#{NUMBER}|#{NUMBER}?[-+]#{NUMBER}?[iIjJ]|#{NUMBER}[iIjJ]|[-+]?[iIjJ]|#{NUMBER})")
      }
    end
    private :forms

    # "1+2i", "3i", "-i", "2.5", "1/2+3/4i", "1@2" (polar).
    def parse(text, exception)
      Primitive.attr! :hidden
      Primitive.attr! :own_backref
      # string_to_c_strict: the text is ASCII-compatible, with no NUL.
      raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{text.encoding}" unless text.encoding.ascii_compatible?
      if text.include?("\0")
        return nil unless exception

        raise ArgumentError, +"string contains null byte"
      end
      body = text.strip
      if (m = forms[:polar].match(body))
        return polar(real_part(m[1]), real_part(m[2]))
      end
      if (m = forms[:pair].match(body)) && (m[2] || m[1].nil?) && !(m[1].nil? && m[2].nil? && m[3].nil? && !%w[i I j J].include?(body))
        real = m[1] ? real_part(m[1]) : 0
        imag = m[3] ? real_part(m[3]) : 1
        imag = -imag if m[2] == +"-"
        return build(real, imag)
      end
      if (m = forms[:imaginary].match(body))
        return build(0, real_part(m[1]))
      end
      if (m = forms[:real].match(body))
        return build(real_part(m[1]), 0)
      end
      zero_denominator(body)
      return nil unless exception

      raise ArgumentError, "invalid value for convert(): #{text.inspect}"
    end
    private :parse

    # read_rat reads a denominator as an integer and divides as soon as it
    # has one, so "1/0.0" and "1/0x2" divide by zero before the rest of
    # the text fails to parse.
    def zero_denominator(body)
      Primitive.attr! :hidden
      slash = body.index("/")
      return unless slash && slash > 0 && body.byteslice(0, slash).each_byte.all? { |b| (b >= 48 && b <= 57) || [43, 45, 46, 69, 95, 101].include?(b) }

      j = slash + 1
      j += 1 while body.getbyte(j) == 48 || (body.getbyte(j) == 95 && body.getbyte(j - 1) == 48)
      b = body.getbyte(j)
      raise ZeroDivisionError, +"divided by 0" if j > slash + 1 && !(b && b >= 48 && b <= 57)
    end
    private :zero_denominator

    def leading(text)
      Primitive.attr! :hidden
      Primitive.attr! :own_backref
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
  # changes only the type of the result to Float.
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

  # comp_mul: each product through safe_mul, so an infinite part times a
  # zero part is a signed zero, not NaN.
  def *(other)
    case other
    when Complex
      ar = real
      ai = imaginary
      br = other.real
      bi = other.imaginary
      arz = ar.zero?
      aiz = ai.zero?
      brz = br.zero?
      biz = bi.zero?
      Complex.send(:build, Complex.send(:safe_mul, ar, br, arz, brz) - Complex.send(:safe_mul, ai, bi, aiz, biz),
                   Complex.send(:safe_mul, ar, bi, arz, biz) + Complex.send(:safe_mul, ai, br, aiz, brz))
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

  # nucomp_to_r: unlike to_f and to_i, a Float zero imaginary part is real.
  def to_r
    raise RangeError, "can't convert #{self} into Rational" unless imaginary == 0

    real.to_r
  end

  def rationalize(eps = nil)
    raise RangeError, "can't convert #{self} into Rational" unless exact_real?

    real.rationalize(eps)
  end

  def to_s = formatted(:to_s)

  def inspect = String.new(+"(", encoding: Encoding::US_ASCII) << formatted(:inspect) << ")"

  # f_format: `a+bi`, each part as `form` writes it -- rb_String for
  # `to_s`, rb_inspect for `inspect` -- and the text takes the encoding
  # the real part's does.
  def formatted(form)
    Primitive.attr! :hidden
    text = +part_text(real, form)
    text << (sign_bit?(imaginary) ? "-" : "+")
    text << part_text(imaginary.is_a?(Float) && imaginary.nan? ? imaginary : imaginary.abs, form)
    text << "*" unless text[-1].match?(/\d/)
    text << "i"
  end

  # CRuby's f_signbit: a Float shows its own sign bit, so -0.0 takes
  # the minus and a NaN does not. Any other value is checked with `< 0`.
  def sign_bit?(v)
    Primitive.attr! :hidden
    return v < 0 unless v.is_a?(Float)

    !v.nan? && (v.negative? || (v.zero? && 1.0 / v < 0))
  end

  private

  def part_text(x, form)
    Primitive.attr! :hidden
    form == :inspect ? Primitive.zr_inspect(x) : Primitive.zr_obj_as_string(x)
  end

  def exact_real?
    Primitive.attr! :hidden
    !imaginary.is_a?(Float) && imaginary == 0
  end

  # A Rational that is whole becomes its Integer.
  def canonical(x)
    Primitive.attr! :hidden
    x.is_a?(Rational) && x.denominator == 1 ? x.numerator : x
  end
end

module Kernel
  def Complex(real, *rest, exception: true)
    raise ArgumentError, "wrong number of arguments (given #{rest.size + 1}, expected 1..2)" if rest.size > 1

    exception = exception_flag(exception)
    return Complex.send(:convert, real, exception) if rest.empty?

    # nucomp_convert with two parts.
    imag = rest.first
    if real.nil? || imag.nil?
      return nil unless exception

      raise TypeError, +"can't convert nil into Complex"
    end
    real = Complex.send(:convert, real, exception) if real.is_a?(String)
    imag = Complex.send(:convert, imag, exception) if imag.is_a?(String)
    return nil if real.nil? || imag.nil?

    # An exact zero imaginary part unwraps here; a Float zero one counts as
    # real below, and nucomp_real_check unwraps it at the end.
    exact_zero = ->(x) { x == 0 && !x.is_a?(Float) }
    realish = ->(x) { x.is_a?(Complex) ? x.imaginary.zero? : x.real? }
    real = real.real if real.is_a?(Complex) && exact_zero.(real.imaginary)
    imag = imag.real if imag.is_a?(Complex) && exact_zero.(imag.imaginary)
    return real if real.is_a?(Complex) && exact_zero.(imag)
    return real + imag * Complex::I if real.is_a?(Numeric) && imag.is_a?(Numeric) && (!realish.(real) || !realish.(imag))

    # With exception: false, an imaginary part that is not a real number
    # gives nil; a real part that is not one raises "not a real" anyway.
    return nil if !exception && !(imag.is_a?(Numeric) && imag.real?) && real.is_a?(Numeric) && real.real?

    Complex.rectangular(real, imag)
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
    # rb_must_asciicompat.
    enc = Encoding.at(Primitive.zr_str_encoding_index_m(self))
    raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{enc}" unless enc.ascii_compatible?

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
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__real__, pair[0])
    Primitive.zr_hidden_set(self, :__imag__, pair[1])
    freeze
  end

  private :marshal_dump, :marshal_load
end
