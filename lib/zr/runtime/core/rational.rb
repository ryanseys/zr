# frozen_string_literal: true

# Rational: an exact fraction of two Integers, the denominator positive
# and the pair reduced. CRuby keeps them in hidden fields; here they are
# hidden ivars, so a Rational shows no instance variables.
class Rational < Numeric
  class << self
    undef_method :new, :allocate

    # A reduced fraction; `d` must not be zero.
    def build(n, d)
      Primitive.attr! :hidden
      raise ZeroDivisionError, +"divided by 0" if d == 0

      if d < 0
        n = -n
        d = -d
      end
      g = n.gcd(d)
      g = 1 if g == 0
      r = Primitive.zr_class_build(self)
      Primitive.zr_hidden_set(r, :__num__, n / g)
      Primitive.zr_hidden_set(r, :__den__, d / g)
      r.freeze
    end
    private :build

    # nurat_s_convert: Kernel#Rational for this class, private.
    def convert(num, *den)
      raise ArgumentError, "wrong number of arguments (given #{den.size + 1}, expected 1..2)" if den.size > 1

      converted(num, den, true)
    end
    private :convert

    # nurat_convert: `num`, over the one element of `den` if it has one,
    # as a Rational of this class; nil when `exception` is false and a
    # part cannot be read.
    def converted(num, den, exception)
      Primitive.attr! :hidden
      given = !den.empty?
      den = den.first
      if NilClass === num || (given && NilClass === den)
        return nil unless exception

        raise TypeError, +"can't convert nil into Rational"
      end
      num = num.real if Complex === num && exact_zero?(num.imaginary)
      den = den.real if Complex === den && exact_zero?(den.imaginary)
      num = readable(num, exception)
      return nil if NilClass === num

      if given
        den = readable(den, exception)
        return nil if NilClass === den
      end
      return num if Rational === num && (!given || exact_one?(den))

      if !given
        unless Integer === num
          return to_rational(num) if exception

          return begin
            to_rational(num)
          rescue StandardError
            nil
          end
        end
      else
        unless Numeric === num
          num = exception ? checked_rational(num) : (to_rational(num) rescue (return nil))
        end
        unless Numeric === den
          den = exception ? checked_rational(den) : (to_rational(den) rescue (return nil))
        end
        if Numeric === num && Numeric === den && !(Integer === num && Integer === den)
          num = begin
            to_rational(num)
          rescue StandardError
            num
          end
          return num / den
        end
      end
      num = int_value(num)
      if !given
        den = 1
      elsif !(Integer === den) && !exception
        return nil
      else
        den = int_value(den)
      end
      build(num, den)
    end

    # One part as nurat_convert reads it first: a Float or a String as
    # a Rational, an object with no to_r through to_int if it has one.
    # nil only for a String that does not read, when `exception` is false.
    def readable(value, exception)
      Primitive.attr! :hidden
      case value
      when Integer, Rational then value
      when Float then value.to_r
      when String
        parsed = parse(value, exception)
        # string_to_r_strict: the zero of a tiny exponent is a Rational,
        # the infinity of a huge one is an error.
        if parsed.is_a?(Float)
          return parsed.to_r if parsed.zero?
          return nil unless exception

          raise FloatDomainError, +"Infinity"
        end
        parsed
      else
        # rb_respond_to; a BasicObject has no respond_to? to ask.
        responds = begin
          value.respond_to?(:to_r)
        rescue NoMethodError
          false
        end
        return value if responds

        int = begin
          Primitive.zr_check_call(value, :to_int)
        rescue StandardError
          nil
        end
        int.is_a?(Integer) ? int : value
      end
    end

    # to_rational: rb_convert_type_with_id with to_r.
    def to_rational(value)
      Primitive.attr! :hidden
      converted = Primitive.zr_check_call(value, :to_r)
      raise TypeError, "can't convert #{conversion_name(value)} into Rational" if converted.nil?

      checked_type(value, converted)
    end

    # rb_check_convert_type_with_id: to_r as rb_check_funcall finds it, a
    # BasicObject's too, or nil when there is none. It must give a Rational.
    def checked_rational(value)
      Primitive.attr! :hidden
      converted = Primitive.zr_check_call(value, :to_r)
      converted.nil? ? nil : checked_type(value, converted)
    end

    def checked_type(value, converted)
      Primitive.attr! :hidden
      return converted if Rational === converted

      raise TypeError, "can't convert #{conversion_name(value)} to Rational (#{conversion_name(value)}#to_r gives #{conversion_name(converted)})"
    end

    # nurat_int_value: only an Integer is an integer here.
    def int_value(value)
      Primitive.attr! :hidden
      raise TypeError, +"not an integer" unless Integer === value

      value
    end

    # k_exact_zero_p and k_exact_one_p: any value but a Float, equal to it.
    def exact_zero?(value)
      Primitive.attr! :hidden
      !(Float === value) && value == 0
    end

    def exact_one?(value)
      Primitive.attr! :hidden
      !(Float === value) && value == 1
    end
    private :converted, :readable, :to_rational, :checked_rational, :checked_type, :int_value, :exact_zero?, :exact_one?

    # parse_rat: a sign, a number with a fraction and an exponent, and an
    # optional `/` and a second such number. `strict` (Rational()) wants
    # nothing else but white space; String#to_r (`exception` is :loose)
    # takes the longest start that reads, and 0 when none does.
    def parse(text, exception)
      Primitive.attr! :hidden
      strict = exception != :loose
      fail = lambda do
        return nil unless exception == true

        raise ArgumentError, "invalid value for convert(): #{text.inspect}"
      end
      return fail.() if strict && text.include?("\0")

      s = skip_space(text, 0)
      sign = nil
      if (b = text.getbyte(s)) && (b == 43 || b == 45)
        sign = b
        s += 1
      end
      num, nexp, s = read_num(text, s)
      return strict ? fail.() : build(0, 1) if num.nil?

      den = 1
      if text.getbyte(s) == 47
        d, dexp, after = read_num(text, s + 1)
        if d.nil?
          return fail.() if strict
        else
          if d.zero?
            return nil if exception == false

            raise ZeroDivisionError, +"divided by 0"
          end

          s = after
          return fail.() if strict && skip_space(text, s) != text.bytesize

          den = d
          nexp -= dexp
        end
      elsif strict && skip_space(text, s) != text.bytesize
        return fail.()
      end
      # An exponent past a fixnum gives a Float, as parse_rat returns one:
      # a zero for a tiny value, an infinity for a huge one.
      unless Primitive.zr_fixnum_p_m(nexp)
        value = nexp.positive? ? 0.0 : Float::INFINITY
        return sign == 45 ? -value : value
      end
      if nexp < 0
        num *= 10**-nexp
      elsif nexp > 0
        den *= 10**nexp
      end
      num = -num if sign == 45
      build(num, den)
    end

    # read_num: [the digits as one Integer, the power of ten that divides
    # it, the byte after], or nil when no digit starts it.
    def read_num(text, s)
      Primitive.attr! :hidden
      num = 0
      nexp = 0
      ok = false
      if text.getbyte(s) != 46
        n, count, s = read_int(text, s)
        return nil if n.nil?

        num = n
        ok = true
      end
      fraction = 0
      if text.getbyte(s) == 46
        s += 1
        fp, count, after = read_int(text, s)
        return [num, nexp, s] if fp.nil?

        s = after
        nexp = count
        num = num * 10**count + fp
        fraction = count
        ok = true
      end
      return nil unless ok

      if s + 1 < text.bytesize && (text.getbyte(s) | 32) == 101
        s += 1
        expsign = nil
        if (b = text.getbyte(s)) && (b == 43 || b == 45)
          expsign = b
          s += 1
        end
        exp, _, after = read_int(text, s)
        return [num, nexp, s] if exp.nil?

        s = after
        nexp = expsign == 45 ? exp + fraction : -(exp - fraction) if exp != 0
      end
      [num, nexp, s]
    end

    # rb_int_parse_cstr with RB_INT_PARSE_UNDERSCORE: digits, each `_`
    # between two of them; [value, count of digits, byte after].
    def read_int(text, s)
      Primitive.attr! :hidden
      digit = ->(i) { (b = text.getbyte(i)) && b >= 48 && b <= 57 }
      return nil unless digit.(s)

      value = 0
      count = 0
      # A leading run of zeros takes single underscores among them and
      # after them, as rb_int_parse_cstr skips them ("0_.1").
      if text.getbyte(s) == 48
        while (b = text.getbyte(s)) && (b == 48 || (b == 95 && text.getbyte(s + 1) != 95 && text.getbyte(s - 1) != 95))
          count += 1 if b == 48
          s += 1
        end
      end
      while true
        if digit.(s)
          value = value * 10 + text.getbyte(s) - 48
          count += 1
          s += 1
        elsif text.getbyte(s) == 95 && digit.(s + 1)
          s += 1
        else
          break
        end
      end
      [value, count, s]
    end

    def skip_space(text, s)
      Primitive.attr! :hidden
      s += 1 while (b = text.getbyte(s)) && (b == 32 || (b >= 9 && b <= 13))
      s
    end
    private :read_num, :read_int, :skip_space
    private :parse
  end

  def numerator = Primitive.zr_hidden_get(self, :__num__)

  def denominator = Primitive.zr_hidden_get(self, :__den__)

  def to_r = self

  def to_i = numerator.abs / denominator * (numerator < 0 ? -1 : 1)

  # nurat_to_double: the quotient rb_int_fdiv_double rounds once.
  def to_f = numerator.fdiv(denominator)

  def to_s = formatted(:to_s)

  def inspect = String.new(+"(", encoding: Encoding::US_ASCII) << formatted(:inspect) << ")"

  def hash = [numerator, denominator, :Rational].hash

  def positive? = numerator > 0

  def negative? = numerator < 0

  def abs = numerator < 0 ? made(-numerator, denominator) : self

  alias magnitude abs

  def -@ = made(-numerator, denominator)

  def +(other)
    case other
    when Integer then made(numerator + other * denominator, denominator)
    when Rational then made(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator)
    when Float then to_f + other
    else coerced(other, :+)
    end
  end

  def -(other)
    case other
    when Integer then made(numerator - other * denominator, denominator)
    when Rational then made(numerator * other.denominator - other.numerator * denominator, denominator * other.denominator)
    when Float then to_f - other
    else coerced(other, :-)
    end
  end

  def *(other)
    case other
    when Integer then made(numerator * other, denominator)
    when Rational then made(numerator * other.numerator, denominator * other.denominator)
    when Float then to_f * other
    else coerced(other, :*)
    end
  end

  def /(other)
    case other
    when Integer
      raise ZeroDivisionError, +"divided by 0" if other == 0

      made(numerator, denominator * other)
    when Rational
      raise ZeroDivisionError, +"divided by 0" if other.numerator == 0

      made(numerator * other.denominator, denominator * other.numerator)
    when Float then to_f / other
    else coerced(other, :/)
    end
  end

  alias quo /

  def fdiv(other) = to_f / other

  def **(other)
    # rb_rational_pow: an exact zero power is one.
    return made(1, 1) if other.is_a?(Numeric) && Rational.send(:exact_zero?, other)

    other = other.numerator if other.is_a?(Rational) && other.denominator == 1
    # 0, 1 and -1 to an exact power, before any Float.
    if (other.is_a?(Integer) || other.is_a?(Rational)) && denominator == 1
      return made(1, 1) if numerator == 1
      return made(other.odd? ? -1 : 1, 1) if numerator == -1 && other.is_a?(Integer)
      if numerator == 0
        raise ZeroDivisionError, +"divided by 0" if other.negative?

        return made(0, 1)
      end
    end
    case other
    when Integer
      # A Bignum power is too large for any result.
      raise ArgumentError, +"exponent is too large" unless other.bit_length < 63

      if other >= 0
        made(numerator**other, denominator**other)
      else
        raise ZeroDivisionError, +"divided by 0" if numerator == 0

        made(denominator**-other, numerator**-other)
      end
    when Float, Rational then to_f**other
    else coerced(other, :**)
    end
  end

  def <=>(other)
    case other
    when Integer then numerator <=> other * denominator
    when Rational then numerator * other.denominator <=> other.numerator * denominator
    when Float then to_f <=> other
    else Primitive.zr_num_coerce_m(self, other, :<=>, 2)
    end
  end

  def ==(other)
    case other
    when Integer then denominator == 1 && numerator == other
    when Rational then numerator == other.numerator && denominator == other.denominator
    when Float then to_f == other
    else other == self
    end
  end

  def coerce(other)
    case other
    when Integer then [Rational.send(:build, other, 1), self]
    when Float then [other, to_f]
    when Rational then [other, self]
    when Complex then other.imaginary == 0 ? [Rational.send(:converted, other.real, [], true), self] : [other, Complex(self)]
    else raise TypeError, "#{other.class} can't be coerced into Rational"
    end
  end

  def floor(digits = 0) = rounded(digits) { |n, d| n.div(d) }

  def ceil(digits = 0) = rounded(digits) { |n, d| -((-n).div(d)) }

  def truncate(digits = 0) = rounded(digits) { |n, d| n < 0 ? -((-n).div(d)) : n.div(d) }

  def round(digits = 0, half: nil)
    half = Numeric.send(:half_mode, half)

    rounded(digits) do |n, d|
      neg = n < 0
      n = -n if neg
      q, r = (n * 2 + d).divmod(d * 2)
      if r == 0
        q -= 1 if half == :down || (half == :even && q.odd?)
      end
      neg ? -q : q
    end
  end

  # The simplest fraction within `eps` of this one.
  def rationalize(eps = nil)
    return self if eps.nil?

    eps = eps.abs
    Rational.send(:simplest, self - eps, self + eps)
  end

  # The fraction with the smallest denominator in [a, b].
  def self.simplest(a, b)
    Primitive.attr! :hidden
    a = Rational.send(:converted, a, [], true)
    b = Rational.send(:converted, b, [], true)
    return a if a == b

    p0 = 0
    p1 = 1
    q0 = 1
    q1 = 0
    loop do
      c = a.ceil
      break Rational.send(:build, c * p1 + p0, c * q1 + q0) if c < b

      k = c - 1
      p2 = k * p1 + p0
      q2 = k * q1 + q0
      t = 1 / (b - k)
      b = 1 / (a - k)
      a = t
      p0 = p1
      q0 = q1
      p1 = p2
      q1 = q2
    end
  end
  private_class_method :simplest

  private

  # `digits` decimal places kept (a Rational), or an Integer for zero or
  # fewer, the block deciding how `n / d` rounds.
  def rounded(digits)
    Primitive.attr! :hidden
    raise TypeError, +"not an integer" unless digits.is_a?(Integer)

    if digits > 0
      scale = 10**digits
      Rational.send(:build, yield(numerator * scale, denominator), scale)
    elsif digits == 0
      yield(numerator, denominator)
    else
      scale = 10**-digits
      yield(numerator, denominator * scale) * scale
    end
  end

  def coerced(other, op)
    Primitive.attr! :hidden
    Primitive.zr_num_coerce_m(self, other, op, 0)
  end

  # A result of this Rational's own class, as CLASS_OF(self) gives it.
  def made(n, d)
    Primitive.attr! :hidden
    Primitive.zr_real_class(self).send(:build, n, d)
  end
end

module Kernel
  def Rational(a, *rest, exception: true)
    raise ArgumentError, "wrong number of arguments (given #{rest.size + 1}, expected 1..2)" if rest.size > 1

    Rational.send(:converted, a, rest, exception_flag(exception))
  end
  private :Rational
  module_function :Rational
end

class Integer
  def to_r = Rational.send(:build, self, 1)

  def rationalize(eps = nil) = to_r

  def numerator = self

  def denominator = 1

end

class Float
  # The exact binary fraction that this double contains.
  def to_r
    raise FloatDomainError, to_s unless finite?
    return Rational.send(:build, 0, 1) if zero?

    mantissa, exponent = Primitive.zr_float_decode(self)
    exponent >= 0 ? Rational.send(:build, mantissa * (1 << exponent), 1) : Rational.send(:build, mantissa, 1 << -exponent)
  end

  # The simplest fraction that reads back as this double, or one within
  # `eps` of it.
  def rationalize(eps = nil)
    raise FloatDomainError, to_s unless finite?
    return Rational.send(:build, 0, 1) if zero?

    if eps.nil?
      mantissa, exponent = Primitive.zr_float_decode(self)
      return Rational.send(:build, mantissa * (1 << exponent), 1) if exponent >= 0

      # The interval is a half unit of the full 53-bit mantissa either
      # way, as CRuby's frexp-based decode gives it.
      while mantissa.abs < (1 << 52)
        mantissa *= 2
        exponent -= 1
      end
      low = Rational.send(:build, 2 * mantissa - 1, 1 << (1 - exponent))
      high = Rational.send(:build, 2 * mantissa + 1, 1 << (1 - exponent))
      Rational.send(:simplest, low, high)
    else
      eps = eps.abs
      Rational.send(:simplest, to_r - eps, to_r + eps)
    end
  end

  # An infinity or NaN is its own numerator over one.
  def numerator = finite? ? to_r.numerator : self

  def denominator = finite? ? to_r.denominator : 1
end

class String
  # string_to_r: the zero of a tiny exponent stays a Float, and the
  # infinity of a huge one is an error.
  def to_r
    parsed = Rational.send(:parse, plain, :loose)
    raise FloatDomainError, +"Infinity" if parsed.is_a?(Float) && !parsed.zero?

    parsed
  end
end

class NilClass
  def to_r = Rational.send(:build, 0, 1)

  # CRuby writes this one in Ruby (its nilclass.rb).
  def rationalize(eps = nil)
    Primitive.attr! :ruby
    to_r
  end
end

class Rational
  # What Marshal writes: the two parts, already in lowest terms.
  def marshal_dump = [numerator, denominator]

  def marshal_load(pair)
    Primitive.attr! :hidden
    raise FrozenError.new("can't modify frozen #{Primitive.zr_real_class(self)}: #{inspect}", receiver: self) if frozen?
    raise TypeError, "wrong argument type #{Primitive.zr_real_class(pair)} (expected Array)" unless pair.is_a?(Array)
    raise ArgumentError, "marshaled rational must have an array whose length is 2 but #{pair.size}" unless pair.size == 2

    # nurat_int_check, then nurat_canonicalize: the sign moves to the
    # numerator, and a zero denominator is a division by zero.
    num, den = pair.map { |part| Rational.send(:int_value, part) }
    raise ZeroDivisionError, +"divided by 0" if den.zero?

    num, den = -num, -den if den.negative?
    Primitive.zr_hidden_set(self, :__num__, num)
    Primitive.zr_hidden_set(self, :__den__, den)
    freeze
  end

  private :marshal_dump, :marshal_load

  private

  # f_format: the numerator and the denominator, each as `form` writes it.
  def formatted(form)
    Primitive.attr! :hidden
    numerator.public_send(form) << "/" << denominator.public_send(form)
  end
end
