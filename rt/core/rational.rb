# Rational: an exact fraction of two Integers, the denominator positive
# and the pair reduced. CRuby keeps them in hidden fields; here they are
# hidden ivars, so a Rational shows no instance variables.
class Rational < Numeric
  class << self
    undef_method :new

    # A reduced fraction; `d` must not be zero.
    def build(n, d)
      Primitive.attr! :hidden
      raise ZeroDivisionError, "divided by 0" if d == 0

      if d < 0
        n = -n
        d = -d
      end
      g = n.gcd(d)
      g = 1 if g == 0
      r = allocate
      Primitive.zr_hidden_set(r, :__num__, n / g)
      Primitive.zr_hidden_set(r, :__den__, d / g)
      r.freeze
    end
    private :build

    # A value of any numeric kind as a Rational, as Kernel#Rational reads
    # it; nil when `exception` is false and it cannot be.
    def convert(value, exception)
      Primitive.attr! :hidden
      case value
      when Integer then build(value, 1)
      when Rational then value
      when Float
        raise FloatDomainError, value.to_s unless value.finite?

        value.to_r
      when String then parse(value, exception)
      when Complex
        raise RangeError, "can't convert #{value} into Rational" unless value.imaginary == 0 && !value.imaginary.is_a?(Float)

        convert(value.real, exception)
      when nil
        return nil unless exception

        raise TypeError, "can't convert nil into Rational"
      else
        if value.respond_to?(:to_r)
          value.to_r
        else
          return nil unless exception

          raise TypeError, "can't convert #{value.class} into Rational"
        end
      end
    end
    private :convert

    # "1/3", "0.75", "-1.5e2", "3": the exact value written.
    def parse(text, exception)
      Primitive.attr! :hidden
      m = /\A\s*([-+])?(\d+(?:_\d+)*)(?:\.(\d+(?:_\d+)*))?(?:[eE]([-+]?\d+))?(?:\/(\d+(?:_\d+)*))?\s*\z/.match(text)
      if m.nil? || text.include?("\0")
        return nil unless exception

        raise ArgumentError, "invalid value for convert(): #{text.inspect}"
      end
      whole = m[2].delete("_")
      frac = (m[3] || "").delete("_")
      n = (whole + frac).to_i
      d = 10**frac.size
      e = m[4].to_i
      if e >= 0
        n *= 10**e
      else
        d *= 10**(-e)
      end
      d *= m[5].delete("_").to_i if m[5]
      raise ZeroDivisionError, "divided by 0" if d == 0

      n = -n if m[1] == "-"
      build(n, d)
    end
    private :parse
  end

  def numerator = Primitive.zr_hidden_get(self, :__num__)

  def denominator = Primitive.zr_hidden_get(self, :__den__)

  def to_r = self

  def to_i = numerator.abs / denominator * (numerator < 0 ? -1 : 1)

  alias truncate_to_i to_i

  def to_f = numerator.to_f / denominator.to_f

  def to_s = "#{numerator}/#{denominator}"

  def inspect = "(#{self})"

  def hash = [numerator, denominator, :Rational].hash

  def zero? = numerator == 0

  def positive? = numerator > 0

  def negative? = numerator < 0

  def integer? = false

  def abs = numerator < 0 ? Rational.send(:build, -numerator, denominator) : self

  alias magnitude abs

  def -@ = Rational.send(:build, -numerator, denominator)

  def +(other)
    case other
    when Integer then Rational.send(:build, numerator + other * denominator, denominator)
    when Rational then Rational.send(:build, numerator * other.denominator + other.numerator * denominator, denominator * other.denominator)
    when Float then to_f + other
    else coerced(other, :+)
    end
  end

  def -(other)
    case other
    when Integer then Rational.send(:build, numerator - other * denominator, denominator)
    when Rational then Rational.send(:build, numerator * other.denominator - other.numerator * denominator, denominator * other.denominator)
    when Float then to_f - other
    else coerced(other, :-)
    end
  end

  def *(other)
    case other
    when Integer then Rational.send(:build, numerator * other, denominator)
    when Rational then Rational.send(:build, numerator * other.numerator, denominator * other.denominator)
    when Float then to_f * other
    else coerced(other, :*)
    end
  end

  def /(other)
    case other
    when Integer
      raise ZeroDivisionError, "divided by 0" if other == 0

      Rational.send(:build, numerator, denominator * other)
    when Rational
      raise ZeroDivisionError, "divided by 0" if other.numerator == 0

      Rational.send(:build, numerator * other.denominator, denominator * other.numerator)
    when Float then to_f / other
    else coerced(other, :/)
    end
  end

  alias quo /

  def fdiv(other) = to_f / other

  def **(other)
    other = other.numerator if other.is_a?(Rational) && other.denominator == 1
    case other
    when Integer
      if other >= 0
        Rational.send(:build, numerator**other, denominator**other)
      else
        raise ZeroDivisionError, "divided by 0" if numerator == 0

        Rational.send(:build, denominator**-other, numerator**-other)
      end
    when Float, Rational then to_f**other
    else coerced(other, :**)
    end
  end

  def %(other)
    return to_f % other if other.is_a?(Float)

    self - other * (self / other).floor
  end

  alias modulo %

  def divmod(other)
    q = (self / other).floor
    [q, self - other * q]
  end

  def div(other) = (self / other).floor

  def remainder(other)
    self - other * (self / other).truncate
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

  def eql?(other) = other.is_a?(Rational) && self == other

  def <(other) = compare(other, :<) < 0

  def <=(other) = compare(other, :<=) <= 0

  def >(other) = compare(other, :>) > 0

  def >=(other) = compare(other, :>=) >= 0

  def coerce(other)
    case other
    when Integer then [Rational.send(:build, other, 1), self]
    when Float then [other, to_f]
    when Rational then [other, self]
    when Complex then other.imaginary == 0 ? [Rational.send(:convert, other.real, true), self] : [other, Complex(self)]
    else raise TypeError, "#{other.class} can't be coerced into Rational"
    end
  end

  def floor(digits = 0) = rounded(digits) { |n, d| n.div(d) }

  def ceil(digits = 0) = rounded(digits) { |n, d| -((-n).div(d)) }

  def truncate(digits = 0) = rounded(digits) { |n, d| n < 0 ? -((-n).div(d)) : n.div(d) }

  def round(digits = 0, half: nil)
    raise ArgumentError, "invalid rounding mode: #{half}" unless [nil, :up, :down, :even].include?(half)

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
    a = Rational.send(:convert, a, true)
    b = Rational.send(:convert, b, true)
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
    raise TypeError, "not an integer" unless digits.is_a?(Integer)

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

  def compare(other, op)
    c = self <=> other
    Primitive.zr_cmperr(self, other) if c.nil?

    c
  end

  def coerced(other, op)
    Primitive.zr_num_coerce_m(self, other, op, 0)
  end
end

module Kernel
  def Rational(a, b = nil, exception: true)
    if b.nil?
      Rational.send(:convert, a, exception)
    else
      x = Rational.send(:convert, a, exception)
      y = Rational.send(:convert, b, exception)
      return nil if x.nil? || y.nil?
      raise ZeroDivisionError, "divided by 0" if y == 0

      r = x / y
      r.is_a?(Rational) ? r : Rational.send(:convert, r, exception)
    end
  end
  private :Rational
  module_function :Rational
end

class Integer
  def to_r = Rational.send(:build, self, 1)

  def rationalize(eps = nil) = to_r

  def numerator = self

  def denominator = 1

  def quo(other)
    return to_f / other if other.is_a?(Float)

    to_r / other
  end
end

class Float
  # The exact binary fraction this double holds.
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

      low = Rational.send(:build, 2 * mantissa - 1, 1 << (1 - exponent))
      high = Rational.send(:build, 2 * mantissa + 1, 1 << (1 - exponent))
      Rational.send(:simplest, low, high)
    else
      eps = eps.abs
      Rational.send(:simplest, to_r - eps, to_r + eps)
    end
  end

  def numerator = to_r.numerator

  def denominator = to_r.denominator
end

class String
  def to_r = Rational.send(:parse, self[/\A\s*[-+]?\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][-+]?\d+)?(?:\/\d[\d_]*)?/] || "0", true)
end

class NilClass
  def to_r = Rational.send(:build, 0, 1)

  def rationalize(eps = nil) = to_r
end
