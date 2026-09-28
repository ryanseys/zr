# frozen_string_literal: true

# Integer over the kernel's arithmetic.
class Integer
  alias inspect to_s
  alias === ==

  # The remainder takes the receiver's sign, as Numeric's rule has it,
  # without a Float or a coercion between two Integers.
  def remainder(other)
    return super unless other.is_a?(Integer)

    r = self % other
    r != 0 && negative? != other.negative? ? r - other : r
  end

  def odd?
    self % 2 == 1
  end

  def even?
    self % 2 == 0
  end

  def zero?
    self == 0
  end

  def -@
    0 - self
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
    return 1 if self == 1 || other == 0
    return other.odd? ? -1 : 1 if self == -1
    return 0 if self == 0
    raise ArgumentError, +"exponent is too large" if pow_too_large?(other)

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

  # rb_big_pow refuses a result of more than 2**34 bits: an exponent that
  # is a Bignum, or bits(x) * y past the limit. A Fixnum base first goes
  # through int_pow, which squares it while it fits in a long, so the
  # check reads x and y where int_pow passes them on.
  def pow_too_large?(y)
    Primitive.attr! :hidden
    fixnum = -(1 << 62)...(1 << 62)
    return true unless fixnum.cover?(y)
    return false if y <= 1

    x = abs
    if fixnum.cover?(x)
      z = y.odd? ? x : 1
      y &= ~1
      loop do
        while y.even?
          return x.bit_length * y > (1 << 34) unless x < 3_037_000_499

          x *= x
          y >>= 1
        end
        return x.bit_length * y > (1 << 34) unless fixnum.cover?(x * z)

        z *= x
        y -= 1
        return false if y == 0
      end
    end
    x.bit_length * y > (1 << 34)
  end

  def pow(exponent, modulus = nil)
    return self**exponent if modulus.nil?
    raise TypeError, +"Integer#pow() 2nd argument not allowed unless a 1st argument is integer" unless exponent.is_a?(Integer)
    raise TypeError, +"Integer#pow() 2nd argument not allowed unless all arguments are integers" unless modulus.is_a?(Integer)
    raise ZeroDivisionError, +"divided by 0" if modulus.zero?
    raise RangeError, +"Integer#pow() 1st argument cannot be negative when 2nd argument specified" if exponent < 0

    result = 1 % modulus
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
      bit = to_integer(bit)
      len = to_integer(len)
      return (self >> bit) & ((1 << len) - 1)
    end
    if bit.is_a?(Range)
      low = bit.begin
      high = bit.end
      if low.nil?
        return 0 if high < 0

        high += 1 unless bit.exclude_end?
        return 0 if (self & ((1 << high) - 1)) == 0

        raise ArgumentError, +"The beginless range for Integer#[] results in infinity"
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

    bit_at(to_integer(bit))
  end

  def bit_at(bit)
    Primitive.attr! :hidden
    return 0 if bit < 0
    return Integer.send(:big_bit_at, self, bit) unless Primitive.zr_fixnum_p_m(self)
    # Past the last bit every bit reads as the sign.
    return negative? ? 1 : 0 if bit >= 62

    (self >> bit) & 1
  end
  private :bit_at

  # Without an encoding: US-ASCII below 128, else one binary byte.
  def chr(encoding = nil)
    if encoding
      encoding = Encoding.find(encoding) unless encoding.is_a?(Encoding)
      index = Encoding.carried(encoding)
      raise RangeError, "#{Primitive.zr_fixnum_p_m(self) ? self : "bignum"} out of char range" if self < 0
      return (+"").force_encoding(encoding).send(:append_unit_point, self) if Encoding.wide?(encoding)
      if encoding.equal?(Encoding::UTF_8) || Encoding.send(:utf8_like?, encoding) || encoding.name == +"CESU-8"
        raise RangeError, "#{Primitive.zr_fixnum_p_m(self) ? self : "bignum"} out of char range" if self > 0x10FFFF
        raise RangeError, "invalid codepoint 0x#{format("%04X", self)} in #{encoding.name}" if self >= 0xD800 && self <= 0xDFFF
        return (+"" << self).force_encoding(encoding) unless encoding.name == +"CESU-8"

        return Encoding.send(:cesu8_bytes, self).pack("C*").force_encoding(encoding)
      end
      # A multibyte encoding's code point is the number its own bytes
      # spell, as rb_enc_codepoint reads one, and the encoding says
      # whether those bytes make a character at all.
      if Encoding.send(:mb?, encoding)
        bytes = []
        value = self
        while value.positive?
          bytes.unshift(value & 0xFF)
          value >>= 8
        end
        bytes = [0] if bytes.empty?
        text = bytes.pack("C*").force_encoding(encoding)
        unless text.length == 1 && text.valid_encoding?
          raise RangeError, "invalid codepoint 0x#{format('%04X', self)} in #{encoding.name}"
        end

        return text
      end
      raise RangeError, "#{Primitive.zr_fixnum_p_m(self) ? self : "bignum"} out of char range" if self > 255

      return Primitive.zr_str_set_index_m(Primitive.zr_str_from_byte(self), index)
    end
    raise RangeError, "#{Primitive.zr_fixnum_p_m(self) ? self : "bignum"} out of char range" if self < 0 || self > 255

    Primitive.zr_str_set_index_m(Primitive.zr_str_from_byte(self), self < 128 ? Encoding::US_ASCII.index : Encoding::BINARY.index)
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

  # CRuby's rb_int_fdiv_double: both sides divided by their gcd first;
  # two that fit divide as doubles, and anything wider goes through
  # big_fdiv, so a quotient in range comes out when each side is past a
  # double. A Float divides the double this is, unless that is infinite:
  # then its 53-bit mantissa divides, as big_fdiv_float does.
  def fdiv(other)
    if other.is_a?(Float)
      dx = to_f
      return dx / other if dx.finite? || other.nan?

      fraction, exp = Primitive.zr_math_frexp(other)
      return Integer.send(:big_fdiv, self, Primitive.zr_math_call(23, fraction, 53).to_i, exp - 53)
    end
    unless other.is_a?(Numeric)
      raise TypeError, "#{conversion_name(other)} can't be coerced into Integer" unless other.respond_to?(:coerce)

      first, second = other.coerce(self)
      return first.fdiv(second)
    end
    return to_f / other unless other.is_a?(Integer) && other != 0

    g = gcd(other)
    x = self / g
    y = other / g
    if Primitive.zr_fixnum_p_m(x)
      return x.to_f / y.to_f if Primitive.zr_fixnum_p_m(y) && y.abs < 2**53
    elsif Primitive.zr_fixnum_p_m(y)
      dx = x.to_f
      return dx / y.to_f unless dx.infinite?
    end
    Integer.send(:big_fdiv, x, y)
  end

  # CRuby's big_fdiv: `x` shifted to 128 bits, as an arithmetic shift
  # rounds, divided by `y` truncating, and scaled back by both shifts.
  # With no `ey`, `y` is first shifted to 64 bits, as big_fdiv_int does.
  def self.big_fdiv(x, y, ey = nil)
    Primitive.attr! :hidden
    if ey.nil?
      ey = y.abs.bit_length - 64
      y >>= ey
    end
    ex = x.abs.bit_length - 128
    if ex > 64
      ex -= 64
    elsif ex > 0
      ex = 0
    end
    x >>= ex
    q = x.abs / y.abs
    q = -q if x.negative? != y.negative?
    Primitive.zr_math_call(23, q.to_f, ex - ey)
  end
  private_class_method :big_fdiv

  def gcdlcm(other) = [gcd(other), lcm(other)]

  def gcd(other)
    raise TypeError, +"not an integer" unless other.is_a?(Integer)

    a = abs
    b = other.abs
    a, b = b, a % b until b.zero?
    a
  end

  def lcm(other)
    raise TypeError, +"not an integer" unless other.is_a?(Integer)
    return 0 if zero? || other.zero?

    (self * other).abs / gcd(other)
  end

  # A fixnum's from its highest bit (zr_fix_bit_length); a bignum's
  # from its limbs.
  def bit_length
    return Primitive.zr_fix_bit_length(self) if Primitive.zr_fixnum_p_m(self)

    Integer.send(:big_bit_length, self)
  end

  def digits(base = 10)
    base = to_integer(base)
    raise ArgumentError, +"negative radix" if base < 0
    raise ArgumentError, "invalid radix #{base}" if base < 2
    raise Math::DomainError, +"out of domain" if negative?

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

  def ceildiv(other)
    Primitive.attr! :ruby
    -(-self).div(other)
  end

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
    return value if Integer === value

    converted = Primitive.zr_check_call(value, :to_int)
    raise TypeError, "can't convert #{conversion_name(value)} to Integer (#{conversion_name(value)}#to_int gives #{conversion_name(converted)})" unless converted.nil? || Integer === converted

    converted
  end

  def self.sqrt(n)
    value = Integer.try_convert(n)
    raise TypeError, "no implicit conversion of #{conversion_name(n)} into Integer" if value.nil?
    raise Math::DomainError, +'Numerical argument is out of domain - "isqrt"' if value < 0
    return value if value < 2

    n = value
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
    Primitive.attr! :hidden
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
  # A number never copies: `clone` and `dup` return the receiver. The
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
    raise ZeroDivisionError, +"divided by 0" if other == 0

    (self / other).floor
  end

  def modulo(other) = self - other * div(other)

  alias % modulo

  def divmod(other) = [div(other), modulo(other)]

  def quo(other) = other.is_a?(Float) ? to_f / other : to_r / other

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

  # CRuby's NUM2INT: an operand as an Integer that fits in a C int, with
  # a RangeError past that range.
  def self.int_operand(n)
    Primitive.attr! :hidden
    n = Primitive.zr_index_operand_m(n)
    return n if n.between?(-2**31, 2**31 - 1)

    raise RangeError, "integer #{n} too #{n.negative? ? "small" : "big"} to convert to 'int'"
  end
  private_class_method :half_mode, :int_operand

  # num_step: `step(limit, step)` or `step(to:, by:)`. Without a block,
  # an ArithmeticSequence over numbers, else an Enumerator; with one,
  # each value up to `limit`. A Float anywhere makes every value a
  # Float, spaced as CRuby's float step is.
  def step(*args, **kwargs, &block)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size > 2

    unknown = kwargs.keys - %i[to by]
    raise ArgumentError, "unknown keyword#{'s' if unknown.size > 1}: #{unknown.map(&:inspect).join(', ')}" unless unknown.empty?

    limit, step = args
    if kwargs.key?(:to)
      raise ArgumentError, +"to is given twice" unless args.empty?

      limit = kwargs[:to]
    end
    if kwargs.key?(:by)
      raise ArgumentError, +"step is given twice" if args.size > 1

      step = kwargs[:by]
    elsif block && args.size > 1 && step.nil?
      raise TypeError, +"step must be numeric"
    end
    raise ArgumentError, +"step can't be 0" if !step.nil? && step == 0

    step = 1 if step.nil?
    unless block
      numeric = (limit.nil? || limit.is_a?(Numeric)) && step.is_a?(Numeric)
      return Enumerator::ArithmeticSequence.for(self, :step, args, kwargs, self, limit, step, false) if numeric

      return to_enum(:step, limit, step)
    end

    stepping(limit, step, &block)
    self
  end

  private

  # num_step's walk: a missing limit is an infinite one in the step's
  # direction, a Float anywhere walks as ruby_float_step does, and any
  # other value is compared with the limit before each yield.
  def stepping(limit, step)
    Primitive.attr! :hidden
    descending = if step.is_a?(Integer) then step.negative?
                 elsif step.respond_to?(:>) then !(step > 0)
                 else raise TypeError, "#{step.class} can't be coerced into Integer"
                 end
    limit = descending ? -Float::INFINITY : Float::INFINITY if limit.nil?
    endless = step == 0 || (limit.is_a?(Float) && limit.infinite? && (limit.negative? ? descending : !descending))
    whole = is_a?(Integer) && step.is_a?(Integer) && (endless || limit.is_a?(Integer))
    if !whole && (is_a?(Float) || limit.is_a?(Float) || step.is_a?(Float))
      return Enumerator::ArithmeticSequence.for(self, :step, [], {}, self, limit, step, false).each { |v| yield v }
    end

    i = self
    if endless
      while true
        yield i
        i += step
      end
    end
    until descending ? i < limit : i > limit
      yield i
      i += step
    end
  end
end
