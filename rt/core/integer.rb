# Integer over the kernel's arithmetic.
class Integer
  def odd?
    self % 2 == 1
  end

  def even?
    self % 2 == 0
  end

  def zero?
    self == 0
  end

  def positive?
    self > 0
  end

  def negative?
    self < 0
  end

  def -@
    0 - self
  end

  def +@
    self
  end

  def succ
    self + 1
  end

  def next
    self + 1
  end

  def pred
    self - 1
  end

  def abs
    self < 0 ? -self : self
  end
end

class Integer
  def <=>(other)
    return Primitive.zr_int_float_spaceship(self, other) if other.is_a?(Float)
    return Primitive.zr_num_coerce_m(self, other, :<=>, 2) unless other.is_a?(Integer)

    self < other ? -1 : (self > other ? 1 : 0)
  end

  def between?(low, high)
    self >= low && self <= high
  end

end

class Integer
  def eql?(other) = other.is_a?(Integer) && self == other
  def hash = self
end

class Integer
  def to_i = self
  alias to_int to_i
  alias truncate to_i

  def integer? = true

  def **(other)
    return to_f**other if other.is_a?(Float)
    other = other.numerator if other.is_a?(Rational) && other.denominator == 1
    return Rational(self, 1)**other if other.is_a?(Rational)
    return Complex(self, 0)**other if other.is_a?(Complex)
    return Primitive.zr_num_coerce_m(self, other, :**, 0) unless other.is_a?(Integer)
    return Rational(1, 1) / (self**-other) if other < 0

    result = 1
    base = self
    n = other
    while n > 0
      result *= base if n.odd?
      n >>= 1
      base *= base if n > 0
    end
    result
  end

  def pow(exponent, modulus = nil)
    return self**exponent if modulus.nil?
    Primitive.zr_unimplemented("Integer#pow with a non-Integer modulus") unless modulus.is_a?(Integer)
    raise ZeroDivisionError, "divided by 0" if modulus.zero?
    Primitive.zr_unimplemented("Integer#pow with a negative exponent") if exponent < 0

    result = 1
    base = self % modulus
    n = exponent
    while n > 0
      result = (result * base) % modulus if n.odd?
      n >>= 1
      base = (base * base) % modulus if n > 0
    end
    result
  end

  def [](bit)
    Primitive.zr_unimplemented("Integer#[] with a range") unless bit.is_a?(Integer)
    return 0 if bit < 0

    (self >> bit) & 1
  end

  # Without an encoding: US-ASCII below 128, else one binary byte.
  def chr(encoding = nil)
    if encoding
      encoding = Encoding.find(encoding) unless encoding.is_a?(Encoding)
      raise RangeError, "#{self} out of char range" if self < 0
      return Primitive.zr_str_set_encoding(+"" << self, 0) if encoding == Encoding::UTF_8
      raise RangeError, "#{self} out of char range" if self > 255

      return Primitive.zr_str_set_encoding(Primitive.zr_str_from_byte(self), encoding == Encoding::BINARY ? 1 : 2)
    end
    raise RangeError, "#{self} out of char range" if self < 0 || self > 255

    Primitive.zr_str_set_encoding(Primitive.zr_str_from_byte(self), self < 128 ? 2 : 1)
  end

  def ord = self

  def divmod(other)
    return to_f.divmod(other) if other.is_a?(Float)

    [div(other), modulo(other)]
  end

  def div(other)
    return (to_f / other).floor if other.is_a?(Float)
    return self / other if other.is_a?(Integer)

    (Primitive.zr_num_coerce_m(self, other, :/, 0)).floor
  end

  def modulo(other) = self % other

  def remainder(other)
    return self - other * (self / other).truncate unless other.is_a?(Integer)

    r = self % other
    r != 0 && (self < 0) != (other < 0) ? r - other : r
  end

  def fdiv(other) = to_f / other

  def abs2 = self * self

  def gcd(other)
    a = abs
    b = other.abs
    a, b = b, a % b until b.zero?
    a
  end

  def lcm(other)
    return 0 if zero? || other.zero?

    (self * other).abs / gcd(other)
  end

  def bit_length
    n = self < 0 ? -self - 1 : self
    bits = 0
    while n > 0
      n >>= 1
      bits += 1
    end
    bits
  end

  def digits(base = 10)
    raise Math::DomainError, "out of domain" if negative?
    raise ArgumentError, "invalid radix #{base}" if base < 2

    return [0] if zero?

    out = []
    n = self
    while n > 0
      out << n % base
      n /= base
    end
    out
  end

  def ceil(digits = 0) = round_to(digits, :ceil)

  def truncate(digits = 0) = round_to(digits, :truncate)

  def allbits?(mask) = self & mask == mask
  def anybits?(mask) = self & mask != 0
  def nobits?(mask) = self & mask == 0

  def ceildiv(other) = -(-self).div(other)

  def floor(digits = 0) = round_to(digits, :floor)

  def round(digits = 0, half: nil) = round_to(digits, :round)

  def self.sqrt(n)
    raise Math::DomainError, 'Numerical argument is out of domain - "isqrt"' if n < 0
    return n if n < 2

    x = n
    y = (x + 1) / 2
    while y < x
      x = y
      y = (x + n / x) / 2
    end
    x
  end

  def size = 8

  def coerce(other)
    return [other, to_f] if other.is_a?(Float)
    return [other, self] if other.is_a?(Integer)

    [Float(other), to_f]
  end

  private

  # Rounding to a negative number of digits; a non-negative count
  # leaves an Integer as it is.
  def round_to(digits, how)
    return self if digits >= 0

    unit = 10**-digits
    low = self - self % unit
    return low if how == :floor
    return low == self ? self : low + unit if how == :ceil
    return negative? ? -(-self - (-self) % unit) : low if how == :truncate

    rem = abs % unit
    nearest = abs - rem
    nearest += unit if rem * 2 >= unit
    negative? ? -nearest : nearest
  end
end

class Numeric
  # `step(limit, step)` or `step(by:, to:)`: an ArithmeticSequence, or
  # each value up to `limit`. A Float anywhere makes every value a
  # Float, spaced as CRuby's float step is.
  def step(limit = nil, step = nil, by: nil, to: nil, &block)
    raise ArgumentError, "to is given twice" if to && !limit.nil?
    raise ArgumentError, "step is given twice" if by && !step.nil?

    limit = to if to
    step = by if by
    raise ArgumentError, "step can't be 0" if step == 0 && !by.nil?
    step = 1 if step.nil?
    raise ArgumentError, "step can't be 0" if step == 0
    raise ArgumentError, "step must be numeric" unless step.is_a?(Numeric)
    return Enumerator::ArithmeticSequence.for(self, limit, step, false) unless block

    Enumerator::ArithmeticSequence.for(self, limit, step, false).each(&block)
    self
  end
end
