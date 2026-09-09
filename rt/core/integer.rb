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
    return nil unless other.is_a?(Integer)

    self < other ? -1 : (self > other ? 1 : 0)
  end

  def between?(low, high)
    self >= low && self <= high
  end

  def clamp(low, high)
    self < low ? low : (self > high ? high : self)
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
    Primitive.zr_unimplemented("Integer#** with a non-Integer exponent") unless other.is_a?(Integer)
    Primitive.zr_unimplemented("Integer#** with a negative exponent, which answers a Rational") if other < 0

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

  def chr
    raise RangeError, "#{self} out of char range" if self < 0 || self > 255
    Primitive.zr_unimplemented("Integer#chr above 127, which needs an encoding") if self > 127

    Primitive.zr_str_from_byte(self)
  end

  def ord = self

  def divmod(other) = [div(other), modulo(other)]

  def div(other)
    Primitive.zr_unimplemented("Integer#div with a non-Integer") unless other.is_a?(Integer)

    self / other
  end

  def modulo(other) = self % other

  def remainder(other)
    Primitive.zr_unimplemented("Integer#remainder with a non-Integer") unless other.is_a?(Integer)

    r = self % other
    r != 0 && (self < 0) != (other < 0) ? r - other : r
  end

  def fdiv(other) = Primitive.zr_unimplemented("Integer#fdiv")

  def to_f = Primitive.zr_unimplemented("Integer#to_f")

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

  def floor(digits = 0) = round_to(digits, :floor)

  def round(digits = 0, half: nil) = round_to(digits, :round)

  def step(limit = nil, step = 1)
    Primitive.zr_unimplemented("Integer#step with a non-Integer") unless (limit.nil? || limit.is_a?(Integer)) && step.is_a?(Integer)
    raise ArgumentError, "step can't be 0" if step.zero?
    return Enumerator::ArithmeticSequence.for(self, limit, step, false) unless block_given?

    i = self
    if step > 0
      while limit.nil? || i <= limit
        yield i
        i += step
      end
    else
      while limit.nil? || i >= limit
        yield i
        i += step
      end
    end
    self
  end

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
    Primitive.zr_unimplemented("Integer#coerce with a non-Integer") unless other.is_a?(Integer)

    [other, self]
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

    rem = abs % unit
    nearest = abs - rem
    nearest += unit if rem * 2 >= unit
    negative? ? -nearest : nearest
  end
end
