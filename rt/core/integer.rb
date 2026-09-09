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
    if other.is_a?(Float)
      return Primitive.zr_int_float_spaceship(self, other) if Primitive.zr_fixnum_p_m(self)

      return Integer.send(:big_cmp_float, self, other)
    end
    return Primitive.zr_num_coerce_m(self, other, :<=>, 2) unless other.is_a?(Integer)

    self < other ? -1 : (self > other ? 1 : 0)
  end

  def between?(low, high)
    self >= low && self <= high
  end

end

class Integer
  def eql?(other) = other.is_a?(Integer) && self == other

  # A bignum's hash folds its limbs; a fixnum is its own.
  def hash = Primitive.zr_fixnum_p_m(self) ? self : [Primitive.zr_hidden_get(self, :__neg__), Primitive.zr_hidden_get(self, :__limbs__)].hash
end

class Integer
  def to_i = self
  alias to_int to_i
  alias truncate to_i

  def integer? = true

  def finite? = true

  def infinite? = nil

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
    raise TypeError, "Integer#pow() 2nd argument not allowed unless a 1st argument is integer" unless exponent.is_a?(Integer)
    raise TypeError, "Integer#pow() 2nd argument not allowed unless all arguments are integers" unless modulus.is_a?(Integer)
    raise ZeroDivisionError, "divided by 0" if modulus.zero?
    raise RangeError, "Integer#pow() 1st argument cannot be negative when 2nd argument specified" if exponent < 0

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

  # `n[i]` is bit i; `n[i, len]` and `n[i..j]` are the bits from i as
  # an Integer, as CRuby's int_aref reads them.
  def [](bit, len = nil)
    unless len.nil?
      bit = Primitive.zr_index_operand_m(bit)
      len = Primitive.zr_index_operand_m(len)
      return (self >> bit) & ((1 << len) - 1)
    end
    if bit.is_a?(Range)
      low = bit.begin
      high = bit.end
      if low.nil?
        return 0 if high < 0

        high += 1 unless bit.exclude_end?
        return 0 if (self & ((1 << high) - 1)) == 0

        raise ArgumentError, "The beginless range for Integer#[] results in infinity"
      end
      shifted = self >> low
      return shifted if high.nil? || low > high
      if low == high
        return 0 if bit.exclude_end?

        return bit_at(low)
      end
      span = high - low
      span += 1 unless bit.exclude_end?
      return shifted & ((1 << span) - 1)
    end

    bit_at(Primitive.zr_index_operand_m(bit))
  end

  def bit_at(bit)
    Primitive.attr! :hidden
    return 0 if bit < 0

    (self >> bit) & 1
  end
  private :bit_at

  # Without an encoding: US-ASCII below 128, else one binary byte.
  def chr(encoding = nil)
    if encoding
      encoding = Encoding.find(encoding) unless encoding.is_a?(Encoding)
      kind = Encoding.walked_index(encoding)
      Primitive.zr_unimplemented("Integer#chr in the #{encoding} encoding") if kind.nil?
      raise RangeError, "#{Primitive.zr_fixnum_p_m(self) ? self : "bignum"} out of char range" if self < 0
      return Primitive.zr_str_set_encoding(+"" << self, 0) if kind == 0
      raise RangeError, "#{Primitive.zr_fixnum_p_m(self) ? self : "bignum"} out of char range" if self > 255

      return Primitive.zr_str_set_encoding(Primitive.zr_str_from_byte(self), kind)
    end
    raise RangeError, "#{Primitive.zr_fixnum_p_m(self) ? self : "bignum"} out of char range" if self < 0 || self > 255

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

  def fdiv(other) = to_f / other

  def abs2 = self * self

  def gcdlcm(other) = [gcd(other), lcm(other)]

  def gcd(other)
    raise TypeError, "not an integer" unless other.is_a?(Integer)

    a = abs
    b = other.abs
    a, b = b, a % b until b.zero?
    a
  end

  def lcm(other)
    raise TypeError, "not an integer" unless other.is_a?(Integer)
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
    base = Primitive.zr_index_operand_m(base)
    raise ArgumentError, "negative radix" if base < 0
    raise ArgumentError, "invalid radix #{base}" if base < 2
    raise Math::DomainError, "out of domain" if negative?

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

  def allbits?(mask)
    mask = bit_mask(mask)
    self & mask == mask
  end

  def anybits?(mask) = self & bit_mask(mask) != 0

  def nobits?(mask) = self & bit_mask(mask) == 0

  # A mask is any Integer, or what to_int makes of the argument.
  def bit_mask(mask)
    Primitive.attr! :hidden
    mask.is_a?(Integer) ? mask : Primitive.zr_index_operand_m(mask)
  end
  private :bit_mask

  alias magnitude abs

  def ceildiv(other) = -(-self).div(other)

  def floor(digits = 0) = round_to(digits, :floor)

  def round(digits = 0, half: nil)
    mode = Numeric.send(:half_mode, half)
    digits = Primitive.zr_index_operand_m(digits)
    return self if digits >= 0

    unit = 10**-digits
    rem = abs % unit
    nearest = abs - rem
    if rem * 2 > unit || (rem * 2 == unit && (mode == :up || (mode == :even && (nearest / unit).odd?)))
      nearest += unit
    end
    negative? ? -nearest : nearest
  end

  # An Integer through `to_int` alone, or nil: `String` is not a form
  # this conversion reads.
  def self.try_convert(value)
    return value if value.is_a?(Integer)
    return nil unless value.respond_to?(:to_int)

    value.to_int
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

  # The bytes a bignum's magnitude takes; a fixnum's word.
  def size = Primitive.zr_fixnum_p_m(self) ? 8 : (bit_length + 7) / 8

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
  # A number never copies: `clone` and `dup` answer the receiver. The
  # default `<=>` knows only that a number equals itself; a subclass
  # that orders its values writes its own.
  def clone(freeze: true)
    raise ArgumentError, "can't unfreeze #{self.class}" if freeze == false

    self
  end

  def dup = self

  def <=>(other) = equal?(other) ? 0 : nil

  def eql?(other) = self.class == other.class && self == other

  # CRuby's rule: the modulo, moved back by the divisor when the signs
  # differ, so the remainder takes the receiver's sign.
  def remainder(other)
    z = self % other
    return z if z == 0

    (self < 0 && other > 0) || (self > 0 && other < 0) ? z - other : z
  end

  def nonzero? = zero? ? nil : self

  def magnitude = abs

  # The defaults a Numeric subclass inherits, each through the
  # operators and conversions the subclass defines.
  def abs = self < 0 ? -self : self

  def -@ = coerce(0).reduce(:-)

  def +@ = self

  def zero? = self == 0

  def positive? = self > 0

  def negative? = self < 0

  def integer? = false

  def finite? = true

  def infinite? = nil

  def div(other)
    raise ZeroDivisionError, "divided by 0" if other == 0

    (self / other).floor
  end

  def modulo(other) = self - other * div(other)

  alias % modulo

  def divmod(other) = [div(other), modulo(other)]

  def quo(other) = to_r / other

  def fdiv(other) = to_f / other

  def to_int = self.to_i

  def numerator = to_r.numerator

  def denominator = to_r.denominator

  def floor(digits = 0) = to_f.floor(digits)

  def ceil(digits = 0) = to_f.ceil(digits)

  def round(digits = 0, half: nil) = to_f.round(digits, half: half)

  def truncate(digits = 0) = to_f.truncate(digits)

  def coerce(other)
    return [other, self] if other.instance_of?(self.class)

    [Float(other), Float(self)]
  end

  # The `half:` keyword as one of :up, :even, :down.
  def self.half_mode(half)
    Primitive.attr! :hidden
    return :up if half.nil?

    name = half.is_a?(String) ? half : half.to_s
    raise ArgumentError, "invalid rounding mode: #{half}" unless half.is_a?(Symbol) || half.is_a?(String)
    return name.to_sym if %w[up even down].include?(name)

    raise ArgumentError, "invalid rounding mode: #{half}"
  end
  private_class_method :half_mode

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

class Integer
  # A number is its own copy.
  def dup = self

  def clone(freeze: nil)
    raise ArgumentError, "can't unfreeze Integer" if freeze == false

    self
  end
end
