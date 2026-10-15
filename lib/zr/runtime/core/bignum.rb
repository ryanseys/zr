# frozen_string_literal: true

# Integers past the fixnum range. A bignum is a plain object of class
# Integer whose magnitude is a little-endian Array of base-2^30 limbs
# and whose sign is a flag, both in hidden instance variables; every
# value that fits a fixnum is one. The kernel's fixnum builtins route
# here (`big_op`) when either side is a bignum.
class Integer
  LIMB_BITS = 30
  LIMB_BASE = 1 << LIMB_BITS
  LIMB_MASK = LIMB_BASE - 1
  # CRuby's limits on a left shift: the count has at most 67 bits (two
  # size_t words, the high one under CHAR_BIT), and the result's 32-bit
  # digits (BDIGIT) number fewer than LONG_MAX / 4. Past 2**31 bits, the
  # result's bytes go to the allocator first.
  SHIFT_COUNT_BITS = 67
  LONG_DIGITS = 0x1FFF_FFFF_FFFF_FFFF
  ROOM_CHECKED_BITS = 0x8000_0000
  # The digits of every base to 36.
  DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
  # The length in limbs from which `to_s` splits a magnitude in two by a
  # power of the base; below it, the kernel divides by one word.
  TO_S_SPLIT = 80
  # By base, the powers that `to_s` splits by, each the square of the
  # one before, with the count of digits that each one shifts.
  POWERS = {}
  private_constant :LIMB_BITS, :LIMB_BASE, :LIMB_MASK, :SHIFT_COUNT_BITS, :LONG_DIGITS, :ROOM_CHECKED_BITS, :DIGITS, :TO_S_SPLIT, :POWERS

  class << self
    # A bignum from a 64-bit word split as `high << 32 | low` by the
    # kernel, for a fixnum sum or difference that overflowed.
    def big_from_word(high, low)
      Primitive.attr! :hidden
      big_add(big_shl(high, 32), low)
    end

    # A bignum from a Float past the fixnum range.
    def big_from_float(f)
      Primitive.attr! :hidden
      mantissa, exponent = Primitive.zr_float_decode(f)
      n = big_shl(mantissa.abs, exponent)
      mantissa < 0 ? big_negate(n) : n
    end

    # The digits of a literal or a String, in `base`, already checked.
    def big_parse(text, base = 10)
      Primitive.attr! :hidden
      neg = text.start_with?("-")
      digits = text.delete("-+_")
      return big_parse_bits(digits, base, neg) if (base & (base - 1)).zero?

      chunk = 1
      per = 0
      while chunk * base < LIMB_BASE
        chunk *= base
        per += 1
      end
      mag = []
      i = 0
      head = digits.size % per
      if head > 0
        mag = big_limbs_of(big_chunk(digits, 0, head, base))
        i = head
      end
      while i < digits.size
        mag = big_add_mag(big_mul_small_mag(mag, chunk), big_limbs_of(big_chunk(digits, i, per, base)))
        i += per
      end
      big_build(neg, mag)
    end

    # The value of the `count` digits at `from`, which fit one limb. It
    # reads the bytes, since String#to_i hands a long run back here.
    def big_chunk(digits, from, count, base)
      Primitive.attr! :hidden
      value = 0
      stop = from + count
      while from < stop
        b = digits.getbyte(from)
        value = value * base + (b <= 57 ? b - 48 : (b | 32) - 87)
        from += 1
      end
      value
    end

    # The limbs of digits in a base that is a power of two, from the last
    # digit's bits up: linear in the length, where a product for each
    # chunk takes the square of it.
    def big_parse_bits(digits, base, neg)
      Primitive.attr! :hidden
      width = base.bit_length - 1
      mag = []
      acc = 0
      held = 0
      i = digits.bytesize - 1
      while i >= 0
        b = digits.getbyte(i)
        acc |= (b <= 57 ? b - 48 : (b | 32) - 87) << held
        held += width
        if held >= LIMB_BITS
          mag << (acc & LIMB_MASK)
          acc >>= LIMB_BITS
          held -= LIMB_BITS
        end
        i -= 1
      end
      mag << acc if acc.positive?
      big_build(neg, mag)
    end

    # --- values ------------------------------------------------------

    def big_build(neg, mag)
      Primitive.attr! :hidden
      mag.pop while !mag.empty? && mag.last == 0
      return 0 if mag.empty?

      if mag.size < 3 || (mag.size == 3 && mag[2] < 4)
        n = mag[0]
        n += mag[1] << LIMB_BITS if mag.size > 1
        n += mag[2] << (2 * LIMB_BITS) if mag.size > 2
        return neg ? -n : n
      end
      if neg && mag.size == 3 && mag[2] == 4 && mag[1] == 0 && mag[0] == 0
        return -(1 << 61) - (1 << 61)
      end
      big = Primitive.zr_big_alloc
      Primitive.zr_hidden_set(big, :__neg__, neg)
      Primitive.zr_hidden_set(big, :__limbs__, mag.freeze)
      big.freeze
    end

    # `n.bit_count` for a bignum `n`: the 1 bits of its limbs, or nil for a
    # negative one.
    def big_bit_count(n)
      Primitive.attr! :hidden
      return nil if big_neg?(n)

      big_mag(n).sum { |limb| Primitive.zr_fix_bit_count(limb) }
    end

    # `n.bit_length` for a bignum `n`: the limbs below the top one are
    # full, and the top one's own bits count; a negative reads through
    # its complement, as a fixnum's does.
    def big_bit_length(n)
      Primitive.attr! :hidden
      return big_bit_length(big_sub(big_negate(n), 1)) if big_neg?(n)

      mag = big_mag(n)
      (mag.size - 1) * LIMB_BITS + mag.last.bit_length
    end

    # Bit `bit` of a bignum `n` (`n[bit]`): a limb's bit for one at or
    # above zero, the shift for one below, whose bits are its
    # complement's.
    def big_bit_at(n, bit)
      Primitive.attr! :hidden
      return (n >> bit) & 1 if big_neg?(n)
      return 0 unless Primitive.zr_fixnum_p_m(bit)

      limb = big_mag(n)[bit / LIMB_BITS]
      limb.nil? ? 0 : (limb >> (bit % LIMB_BITS)) & 1
    end

    # The limbs of |n|, n any Integer.
    def big_mag(n)
      Primitive.attr! :hidden
      return Primitive.zr_hidden_get(n, :__limbs__) unless Primitive.zr_fixnum_p_m(n)

      big_limbs_of(n < 0 ? -n : n)
    end

    def big_neg?(n)
      Primitive.attr! :hidden
      return Primitive.zr_hidden_get(n, :__neg__) unless Primitive.zr_fixnum_p_m(n)

      n < 0
    end

    # The limbs of a non-negative fixnum.
    def big_limbs_of(n)
      Primitive.attr! :hidden
      out = []
      while n > 0
        out << (n & LIMB_MASK)
        n >>= LIMB_BITS
      end
      out
    end

    def big_negate(n)
      Primitive.attr! :hidden
      big_build(!big_neg?(n), big_mag(n).dup)
    end

    # --- magnitudes ----------------------------------------------------
    #
    # The loops are in the kernel (lib/zr/runtime/kernel/bignum.rb).

    def big_cmp_mag(a, b)
      Primitive.attr! :hidden
      Primitive.zr_big_cmp_mag(a, b)
    end

    def big_add_mag(a, b)
      Primitive.attr! :hidden
      Primitive.zr_big_add_mag(a, b)
    end

    # `a - b` for a >= b.
    def big_sub_mag(a, b)
      Primitive.attr! :hidden
      Primitive.zr_big_sub_mag(a, b)
    end

    def big_mul_mag(a, b)
      Primitive.attr! :hidden
      Primitive.zr_big_mul_mag(a, b)
    end

    # `a * m` for a fixnum m below the limb base.
    def big_mul_small_mag(a, m)
      Primitive.attr! :hidden
      Primitive.zr_big_mul_small_mag(a, m)
    end

    # `[quotient, remainder]` of a magnitude by a fixnum above zero and
    # below the limb base; the remainder is a fixnum.
    def big_divmod_small_mag(a, m)
      Primitive.attr! :hidden
      Primitive.zr_big_divmod_small_mag(a, m)
    end

    # `[quotient, remainder]` magnitudes, by Knuth's algorithm D for a
    # divisor of two limbs or more.
    def big_divmod_mag(a, b)
      Primitive.attr! :hidden
      return [[], a.dup] if big_cmp_mag(a, b) < 0
      if b.size == 1
        q, r = big_divmod_small_mag(a, b[0])
        return [q, r == 0 ? [] : [r]]
      end

      Primitive.zr_big_divmod_mag(a, b)
    end

    # A magnitude shifted left `bits` (any count) or right (below the
    # limb width, bits lost).
    def big_shl_mag(a, bits)
      Primitive.attr! :hidden
      return a.dup if bits == 0

      limbs = bits / LIMB_BITS
      bits %= LIMB_BITS
      out = Array.new(limbs, 0)
      carry = 0
      i = 0
      while i < a.size
        t = (a[i] << bits) | carry
        out << (t & LIMB_MASK)
        carry = t >> LIMB_BITS
        i += 1
      end
      out << carry if carry > 0
      out.pop while !out.empty? && out.last == 0
      out
    end

    def big_shr_mag(a, bits)
      Primitive.attr! :hidden
      return a.dup if bits == 0

      out = Array.new(a.size, 0)
      carry = 0
      i = a.size - 1
      while i >= 0
        out[i] = (a[i] >> bits) | carry
        carry = (a[i] << (LIMB_BITS - bits)) & LIMB_MASK
        i -= 1
      end
      out.pop while !out.empty? && out.last == 0
      out
    end

    # --- signed arithmetic ----------------------------------------------

    def big_add(x, y)
      Primitive.attr! :hidden
      big_sum(big_mag(x), big_neg?(x), big_mag(y), big_neg?(y))
    end

    # `x + -y`, with no copy of y.
    def big_sub(x, y)
      Primitive.attr! :hidden
      big_sum(big_mag(x), big_neg?(x), big_mag(y), !big_neg?(y))
    end

    # The sum of two magnitudes, each with its sign.
    def big_sum(xm, xn, ym, yn)
      Primitive.attr! :hidden
      if xn == yn
        big_build(xn, big_add_mag(xm, ym))
      elsif big_cmp_mag(xm, ym) >= 0
        big_build(xn, big_sub_mag(xm, ym))
      else
        big_build(!xn, big_sub_mag(ym, xm))
      end
    end

    # A factor below the limb base takes one pass and no limb Array of
    # its own.
    def big_mul(x, y)
      Primitive.attr! :hidden
      neg = big_neg?(x) != big_neg?(y)
      return big_build(neg, big_mul_small_mag(big_mag(x), y.abs)) if big_small?(y)
      return big_build(neg, big_mul_small_mag(big_mag(y), x.abs)) if big_small?(x)

      big_build(neg, big_mul_mag(big_mag(x), big_mag(y)))
    end

    # Whether `n` is a fixnum whose size is below the limb base.
    def big_small?(n)
      Primitive.attr! :hidden
      Primitive.zr_fixnum_p_m(n) && n > -LIMB_BASE && n < LIMB_BASE
    end

    # Floored `[quotient, remainder]`, the remainder taking the
    # divisor's sign.
    def big_divmod(x, y)
      Primitive.attr! :hidden
      raise ZeroDivisionError, +"divided by 0" if y == 0

      qm, rm = big_divmod_mag(big_mag(x), big_mag(y))
      xn = big_neg?(x)
      yn = big_neg?(y)
      if xn == yn
        [big_build(false, qm), big_build(yn, rm)]
      elsif rm.empty?
        [big_build(true, qm), 0]
      else
        [big_sub(big_build(true, qm), 1), big_build(yn, big_sub_mag(big_mag(y), rm))]
      end
    end

    def big_shl(x, bits)
      Primitive.attr! :hidden
      return big_shr(x, -bits) if bits < 0

      big_build(big_neg?(x), big_shl_mag(big_mag(x), bits))
    end

    # A right shift floors: a negative value with lost bits moves one
    # further from zero.
    def big_shr(x, bits)
      Primitive.attr! :hidden
      return big_shl(x, -bits) if bits < 0

      mag = big_mag(x)
      limbs = bits / LIMB_BITS
      rest = bits % LIMB_BITS
      lost = mag[0, limbs].any? { |l| l != 0 } || (limbs < mag.size && rest > 0 && (mag[limbs] & ((1 << rest) - 1)) != 0)
      kept = big_shr_mag(mag[limbs..] || [], rest)
      n = big_build(big_neg?(x), kept)
      big_neg?(x) && lost ? big_sub(n, 1) : n
    end

    def big_cmp(x, y)
      Primitive.attr! :hidden
      xn = big_neg?(x)
      yn = big_neg?(y)
      return (xn ? -1 : 1) if xn != yn

      c = big_cmp_mag(big_mag(x), big_mag(y))
      xn ? -c : c
    end

    # Bitwise operations run over two's complement limbs, with the sign
    # represented by an infinite run of ones.
    def big_twos(x, len)
      Primitive.attr! :hidden
      if big_neg?(x)
        mag = big_sub_mag(big_mag(x), [1])
        Array.new(len) { |i| (i < mag.size ? mag[i] : 0) ^ LIMB_MASK }
      else
        mag = big_mag(x)
        Array.new(len) { |i| i < mag.size ? mag[i] : 0 }
      end
    end

    def big_from_twos(limbs, neg)
      Primitive.attr! :hidden
      return big_build(false, limbs) unless neg

      big_build(true, big_add_mag(limbs.map { |l| l ^ LIMB_MASK }, [1]))
    end

    def big_bitwise(x, y, op)
      Primitive.attr! :hidden
      x_size = big_mag(x).size
      y_size = big_mag(y).size
      len = (x_size > y_size ? x_size : y_size) + 1
      a = big_twos(x, len)
      b = big_twos(y, len)
      xn = big_neg?(x)
      yn = big_neg?(y)
      case op
      when :& then big_from_twos(Array.new(len) { |i| a[i] & b[i] }, xn && yn)
      when :| then big_from_twos(Array.new(len) { |i| a[i] | b[i] }, xn || yn)
      else big_from_twos(Array.new(len) { |i| a[i] ^ b[i] }, xn != yn)
      end
    end

    # Digits in `base`. A base that is a power of two reads the bits; any
    # other divides, in the kernel below TO_S_SPLIT limbs, and above it
    # splits the value in two halves of digits first.
    def big_to_s(x, base)
      Primitive.attr! :hidden
      return big_to_s_bits(x, base) if (base & (base - 1)).zero?

      mag = big_mag(x)
      return Primitive.zr_big_to_digits(mag, base, big_neg?(x), 0) if mag.size < TO_S_SPLIT

      big_digits_into(+(big_neg?(x) ? "-" : ""), mag, base, 0).force_encoding(Encoding::US_ASCII)
    end

    # Appends to `text` the digits of the magnitude `mag`, with zeros in
    # front up to `width`: the digits of `mag` divided by the largest
    # power of the base with at most half its limbs, then those of the
    # remainder, which fill exactly the power's digits.
    def big_digits_into(text, mag, base, width)
      Primitive.attr! :hidden
      return text << Primitive.zr_big_to_digits(mag, base, false, width) if mag.size < TO_S_SPLIT

      power, digits = big_to_s_power(base, mag.size / 2)
      high, low = big_divmod_mag(mag, power)
      big_digits_into(text, high, base, width - digits)
      big_digits_into(text, low, base, digits)
    end

    # The largest power of `base` that POWERS keeps, or makes, with at
    # most `limbs` limbs, and its count of digits. The first is the
    # largest power below the limb base.
    def big_to_s_power(base, limbs)
      Primitive.attr! :hidden
      powers = POWERS[base] ||= begin
        chunk = base
        per = 1
        while chunk * base < LIMB_BASE
          chunk *= base
          per += 1
        end
        [[[chunk], per]]
      end
      while powers.last[0].size * 2 <= limbs
        mag, digits = powers.last
        powers << [big_mul_mag(mag, mag), digits * 2]
      end
      powers.reverse_each.find { |mag, _| mag.size <= limbs }
    end

    # The digits of a base that is a power of two, the lowest first from
    # the limbs' bits, then turned: linear in the length, where division
    # takes the square of it.
    def big_to_s_bits(x, base)
      Primitive.attr! :hidden
      width = base.bit_length - 1
      text = +""
      acc = 0
      held = 0
      big_mag(x).each do |limb|
        acc |= limb << held
        held += LIMB_BITS
        while held >= width
          text << DIGITS.getbyte(acc & (base - 1))
          acc >>= width
          held -= width
        end
      end
      text << DIGITS.getbyte(acc) if acc.positive?
      text.reverse!
      text.sub!(/\A0+/, "")
      text.prepend("-") if big_neg?(x)
      text.force_encoding(Encoding::US_ASCII)
    end

    # The nearest double: the top 62 bits with a sticky bit for the
    # rest, scaled by the bits dropped, so the one rounding is right.
    def big_to_f(x)
      Primitive.attr! :hidden
      mag = big_mag(x)
      bits = (mag.size - 1) * LIMB_BITS + mag.last.bit_length
      drop = bits - 62
      top = big_build(false, big_shr_mag(mag[(drop / LIMB_BITS)..], drop % LIMB_BITS))
      sticky = mag[0, drop / LIMB_BITS].any? { |l| l != 0 } || (mag[drop / LIMB_BITS] & ((1 << (drop % LIMB_BITS)) - 1)) != 0
      top |= 1 if sticky
      # top fits a fixnum, and `top * 1.0` converts it natively: a
      # program's Integer#to_f may itself convert a Bignum.
      f = (top * 1.0) * (2.0**drop)
      Primitive.zr_warn_here_m("Integer out of Float range") if f.infinite? && $VERBOSE
      big_neg?(x) ? -f : f
    end

    # `x << n` when `left`, else `x >> n`. A Bignum count moves every bit
    # out to the right: it leaves 0, or -1 below zero. To the left, CRuby's
    # big_shift2 and big_shift3 refuse a count of 2**67 or more and a
    # result of LONG_MAX bytes or more, then allocate the result's
    # digits, which raises NoMemoryError when the allocator cannot supply
    # them.
    def big_shift(x, n, left)
      Primitive.attr! :hidden
      return 0 if x.zero?

      left = !left if n.negative?
      count = n.abs
      unless left
        return x.negative? ? -1 : 0 unless Primitive.zr_fixnum_p_m(count)

        return big_shr(x, count)
      end
      # Only a result of 256 MB or more needs the allocator's answer.
      if count >= ROOM_CHECKED_BITS
        digits = (count >> 5) + ((x.abs.bit_length + 31) >> 5)
        raise RangeError, +"shift width too big" if count.bit_length > SHIFT_COUNT_BITS || digits >= LONG_DIGITS

        bytes = (digits + 1) * 4
        Primitive.zr_no_memory unless Primitive.zr_fixnum_p_m(bytes) && Primitive.zr_memory_for_p(bytes)
      end
      big_shl(x, count)
    end

    # An exact comparison with a Float: through its integer part, then
    # its fraction.
    def big_cmp_float(x, f)
      Primitive.attr! :hidden
      return nil if f.nan?
      return (f > 0 ? -1 : 1) if f.infinite?

      c = big_cmp(x, f.floor)
      c == 0 && f % 1.0 != 0.0 ? -1 : c
    end
  end

  private_class_method :big_from_word, :big_from_float, :big_parse, :big_parse_bits, :big_build, :big_mag, :big_neg?, :big_limbs_of, :big_negate, :big_cmp_mag, :big_add_mag, :big_sub_mag, :big_mul_mag, :big_mul_small_mag, :big_divmod_small_mag, :big_divmod_mag, :big_shl_mag, :big_shr_mag, :big_add, :big_sub, :big_sum, :big_mul, :big_small?, :big_divmod, :big_shl, :big_shr, :big_cmp, :big_twos, :big_from_twos, :big_bitwise, :big_to_s, :big_digits_into, :big_to_s_power, :big_to_s_bits, :big_to_f, :big_shift, :big_cmp_float

  # The kernel's route for a fixnum builtin whose receiver or operand
  # is a bignum: `op` is the builtin's name, then its arguments. An
  # operator's one operand takes no Array.
  def big_op(op, other = (given = 0; nil), *more)
    Primitive.attr! :hidden
    case op
    when :to_s
      raise ArgumentError, wrong_arity(1 + Primitive.zr_ary_len_m(more), 0..1) unless Primitive.zr_ary_len_m(more) == 0

      base = given == 0 ? 10 : Primitive.zr_index_operand_m(other)
      raise ArgumentError, "invalid radix #{base}" if base < 2 || base > 36

      Integer.send(:big_to_s, self, base)
    when :to_f then Integer.send(:big_to_f, self)
    when :~ then Integer.send(:big_sub, Integer.send(:big_negate, self), 1)
    when :times
      return to_enum(:times) { negative? ? 0 : self } unless block_given?

      i = 0
      while i < self
        yield i
        i += 1
      end
      self
    when :upto
      return to_enum(:upto, other) { other >= self ? (other - self).div(1) + 1 : 0 } unless block_given?

      i = self
      while i <= other
        yield i
        i += 1
      end
      self
    when :downto
      return to_enum(:downto, other) { self >= other ? (other - self).div(-1) + 1 : 0 } unless block_given?

      i = self
      while i >= other
        yield i
        i -= 1
      end
      self
    when :==, :!=
      same = case other
             when Integer then Integer.send(:big_cmp, self, other) == 0
             when Float then Integer.send(:big_cmp_float, self, other) == 0
             else (other == self) ? true : false
             end
      op == :== ? same : !same
    when :+, :-, :*, :/, :%, :<<, :>>, :&, :|, :^, :<, :<=, :>, :>=
      big_binary(op, other)
    else raise NoMethodError, "undefined method '#{op}' for an instance of Integer"
    end
  end

  private

  def big_binary(op, other)
    Primitive.attr! :hidden
    # A shift count converts as CRuby's rb_to_int does: a Float or a
    # Rational truncates.
    return big_with_integer(op, to_integer(other)) if (op == :<< || op == :>>) && !other.is_a?(Integer)

    case other
    when Integer then big_with_integer(op, other)
    when Float
      case op
      when :+ then to_f + other
      when :- then to_f - other
      when :* then to_f * other
      when :/ then to_f / other
      when :% then to_f % other
      when :<, :<=, :>, :>=
        # Nothing orders against NaN: every relation is false.
        c = Integer.send(:big_cmp_float, self, other)
        return false if c.nil?

        op == :< ? c < 0 : (op == :<= ? c <= 0 : (op == :> ? c > 0 : c >= 0))
      # A bit operator coerces, then calls the operator of the first of
      # the pair, as rb_num_coerce_bit does.
      when :&, :|, :^ then Primitive.zr_num_coerce_m(self, other, op, 4)
      else raise TypeError, +"no implicit conversion from Float"
      end
    else
      kind = %i[< <= > >=].include?(op) ? 1 : (%i[& | ^].include?(op) ? 4 : 0)
      Primitive.zr_num_coerce_m(self, other, op, kind)
    end
  end

  def big_with_integer(op, other)
    Primitive.attr! :hidden
    case op
    when :+ then Integer.send(:big_add, self, other)
    when :- then Integer.send(:big_sub, self, other)
    when :* then Integer.send(:big_mul, self, other)
    when :/ then Integer.send(:big_divmod, self, other)[0]
    when :% then Integer.send(:big_divmod, self, other)[1]
    when :<< then Integer.send(:big_shift, self, other, true)
    when :>> then Integer.send(:big_shift, self, other, false)
    when :&, :|, :^ then Integer.send(:big_bitwise, self, other, op)
    when :< then Integer.send(:big_cmp, self, other) < 0
    when :<= then Integer.send(:big_cmp, self, other) <= 0
    when :> then Integer.send(:big_cmp, self, other) > 0
    when :>= then Integer.send(:big_cmp, self, other) >= 0
    end
  end

end
