# C's strtod for WASI, which has no libc strtod in a zr module. The
# result is correctly rounded (round half to even), as musl's is.
#
# A short decimal goes the fast path (Clinger): a mantissa below 2**53
# and a power of ten up to 1e22 are exact doubles, so one multiply or
# divide rounds once. Any other decimal goes the exact path, which is
# a port of Go's strconv (decimal.go and the decimal path of atof.go,
# Copyright 2009 The Go Authors, BSD-3-Clause; see THIRD_PARTY_NOTICES.md
# and licenses/go.txt): the digits go into a buffer of 800 decimal
# digits, and shifts by powers of two move the value into [0.5, 1).
# The digits after the 800th only set the `trunc` flag, which the
# rounding reads. 800 digits are more than the 767 significant digits
# of the longest halfway case.

module Zr::Kern
  # Go's `decimal`: `nd` digits (each 0..9) after the header, with the
  # decimal point `dp` digits after the first digit. `trunc` is 1 when
  # a digit that is not zero was dropped.
  class StrtodDecimal < Layout
    attr_accessor :nd #: word
    attr_accessor :dp #: word
    attr_accessor :trunc #: word
  end

  STRTOD_DIGITS = 800
  # The largest shift in one pass. 5**27 is below 2**63, so the cutoff
  # of a left shift fits a word.
  STRTOD_MAX_SHIFT = 27

  # The byte at `s + i`, from 0 to 255.
  #: (ptr, word) -> word
  def zr_strtod_at(s, i)
    Machine.u8(Machine.load8(s + i, 0))
  end

  # The value of the hex digit `c`, or -1.
  #: (word) -> word
  def zr_strtod_hex_value(c)
    if c >= 48 && c <= 57
      return c - 48
    end
    if c >= 97 && c <= 102
      return c - 87
    end
    if c >= 65 && c <= 70
      return c - 55
    end
    -1
  end

  # Whether the text at `s + i` starts with the `n` lowercase letters at
  # `word`, in any case.
  #: (ptr, word, ptr, word) -> bool
  def zr_strtod_word_p(s, i, word, n)
    j = 0
    while j < n
      if (zr_strtod_at(s, i + j) | 32) != zr_strtod_at(word, j)
        return false
      end
      j += 1
    end
    true
  end

  # strtod(3): reads a number at `s` and returns it. When `stop` is not 0,
  # it stores at `stop` the address after the last byte that it read, or
  # `s` when no number starts there. It reads leading white space, a sign,
  # then a decimal number with an optional exponent, a hex number
  # ("0x1.8p+3"), "inf", "infinity" or "nan" with an optional "(chars)".
  #: (ptr, ptr) -> f64
  def strtod(s, stop)
    i = 0
    while zr_strtod_at(s, i) == 32 || (zr_strtod_at(s, i) >= 9 && zr_strtod_at(s, i) <= 13)
      i += 1
    end
    neg = false
    if zr_strtod_at(s, i) == 45
      neg = true
      i += 1
    elsif zr_strtod_at(s, i) == 43
      i += 1
    end
    if zr_strtod_at(s, i) == 48 && (zr_strtod_at(s, i + 1) | 32) == 120 &&
       (zr_strtod_hex_value(zr_strtod_at(s, i + 2)) >= 0 ||
        (zr_strtod_at(s, i + 2) == 46 && zr_strtod_hex_value(zr_strtod_at(s, i + 3)) >= 0))
      return zr_strtod_hex(s, i + 2, neg, stop)
    end
    if zr_strtod_word_p(s, i, Machine.bytes("infinity"), 8)
      zr_strtod_stop(stop, s + i + 8)
      return zr_strtod_signed(Machine.f64(0x7FF0000000000000), neg)
    end
    if zr_strtod_word_p(s, i, Machine.bytes("inf"), 3)
      zr_strtod_stop(stop, s + i + 3)
      return zr_strtod_signed(Machine.f64(0x7FF0000000000000), neg)
    end
    if zr_strtod_word_p(s, i, Machine.bytes("nan"), 3)
      i += 3
      if zr_strtod_at(s, i) == 40
        j = i + 1
        c = zr_strtod_at(s, j)
        while (c >= 48 && c <= 57) || ((c | 32) >= 97 && (c | 32) <= 122) || c == 95
          j += 1
          c = zr_strtod_at(s, j)
        end
        i = j + 1 if c == 41
      end
      zr_strtod_stop(stop, s + i)
      return zr_strtod_signed(Machine.f64(0x7FF8000000000000), neg)
    end
    zr_strtod_decimal(s, i, neg, stop)
  end

  #: (ptr, ptr) -> void
  def zr_strtod_stop(stop, at)
    Machine.store64(stop, 0, at) if stop != 0
  end

  #: (f64, bool) -> f64
  def zr_strtod_signed(x, neg)
    neg ? -x : x
  end

  # The decimal number at `s + i`, after its sign. Fills the digit buffer
  # and the short mantissa together, as Go's readFloat and decimal.set do.
  #: (ptr, word, bool, ptr) -> f64
  def zr_strtod_decimal(s, i, neg, stop)
    d = Machine.slot(StrtodDecimal.size + STRTOD_DIGITS)
    digits = d + StrtodDecimal.size
    nd = 0
    dp = 0
    trunc = 0
    # The first 18 significant digits, for the fast path; `mtrunc` is
    # true when a later digit is not zero.
    mant = 0
    mnd = 0
    mtrunc = false
    sawdot = false
    sawdigits = false
    while true
      c = zr_strtod_at(s, i)
      if c == 46
        break if sawdot

        sawdot = true
        dp = nd
      elsif c >= 48 && c <= 57
        sawdigits = true
        if c == 48 && nd == 0
          # A leading zero moves only the point.
          dp -= 1
        else
          if nd < STRTOD_DIGITS
            Machine.store8(digits + nd, 0, Machine.i8(c - 48))
          elsif c != 48
            trunc = 1
          end
          nd += 1
          if mnd < 18
            mant = (mant * 10) + c - 48
            mnd += 1
          elsif c != 48
            mtrunc = true
          end
        end
      else
        break
      end
      i += 1
    end
    unless sawdigits
      zr_strtod_stop(stop, s)
      return Machine.f64(0)
    end
    dp = nd unless sawdot
    if (zr_strtod_at(s, i) | 32) == 101
      j = i + 1
      esign = 1
      if zr_strtod_at(s, j) == 43
        j += 1
      elsif zr_strtod_at(s, j) == 45
        esign = -1
        j += 1
      end
      c = zr_strtod_at(s, j)
      if c >= 48 && c <= 57
        e = 0
        while c >= 48 && c <= 57
          e = (e * 10) + c - 48 if e < 10000
          j += 1
          c = zr_strtod_at(s, j)
        end
        dp += esign * e
        i = j
      end
    end
    zr_strtod_stop(stop, s + i)
    exp10 = mant == 0 ? 0 : dp - mnd
    unless mtrunc
      # Clinger's fast path: Go's atof64exact.
      if mant < (1 << 53)
        f = Machine.to_f64(mant)
        if exp10 == 0
          return zr_strtod_signed(f, neg)
        end
        if exp10 > 0 && exp10 <= 37
          if exp10 > 22
            f = f * zr_strtod_pow10(exp10 - 22)
            exp10 = 22
          end
          if f <= Machine.f64(0x430C6BF526340000) # 1e15
            return zr_strtod_signed(f * zr_strtod_pow10(exp10), neg)
          end
        elsif exp10 < 0 && exp10 >= -22
          return zr_strtod_signed(f / zr_strtod_pow10(-exp10), neg)
        end
      end
    end
    nd = STRTOD_DIGITS if nd > STRTOD_DIGITS
    StrtodDecimal[d].nd = nd
    StrtodDecimal[d].dp = dp
    StrtodDecimal[d].trunc = trunc
    zr_strtod_trim(d)
    bits = zr_strtod_float_bits(d)
    bits |= Machine.word(0x8000000000000000) if neg
    Machine.f64(bits)
  end

  # 10**k for k in 0..22, each exact.
  #: (word) -> f64
  def zr_strtod_pow10(k)
    p = Machine.f64(0x3FF0000000000000) # 1.0
    ten = Machine.f64(0x4024000000000000)
    j = 0
    while j < k
      p = p * ten
      j += 1
    end
    p
  end

  # The digit `i` of `d`.
  #: (ptr, word) -> word
  def zr_strtod_digit(d, i)
    Machine.sword(Machine.load8(d + StrtodDecimal.size + i, 0))
  end

  #: (ptr, word, word) -> void
  def zr_strtod_set_digit(d, i, v)
    Machine.store8(d + StrtodDecimal.size + i, 0, Machine.i8(v))
  end

  # Drops the trailing zeros (Go's trim).
  #: (ptr) -> void
  def zr_strtod_trim(d)
    nd = StrtodDecimal[d].nd
    while nd > 0 && zr_strtod_digit(d, nd - 1) == 0
      nd -= 1
    end
    StrtodDecimal[d].nd = nd
    StrtodDecimal[d].dp = 0 if nd == 0
  end

  # Divides by 2**k, k at most STRTOD_MAX_SHIFT (Go's rightShift).
  #: (ptr, word) -> void
  def zr_strtod_right_shift(d, k)
    nd = StrtodDecimal[d].nd
    r = 0
    w = 0
    n = 0
    while (n >> k) == 0
      if r >= nd
        if n == 0
          StrtodDecimal[d].nd = 0
          return
        end
        while (n >> k) == 0
          n *= 10
          r += 1
        end
        break
      end
      n = (n * 10) + zr_strtod_digit(d, r)
      r += 1
    end
    StrtodDecimal[d].dp = StrtodDecimal[d].dp - (r - 1)
    mask = (1 << k) - 1
    while r < nd
      c = zr_strtod_digit(d, r)
      zr_strtod_set_digit(d, w, n >> k)
      w += 1
      n = ((n & mask) * 10) + c
      r += 1
    end
    while n > 0
      dig = n >> k
      n &= mask
      if w < STRTOD_DIGITS
        zr_strtod_set_digit(d, w, dig)
        w += 1
      elsif dig > 0
        StrtodDecimal[d].trunc = 1
      end
      n *= 10
    end
    StrtodDecimal[d].nd = w
    zr_strtod_trim(d)
  end

  # Whether the digits of `d` are below the digits of 5**k as a prefix
  # (Go's prefixIsLessThan with the cutoff of leftcheats).
  #: (ptr, word) -> bool
  def zr_strtod_below_pow5(d, k)
    p5 = 1
    j = 0
    while j < k
      p5 *= 5
      j += 1
    end
    scale = 1
    while scale <= p5 / 10
      scale *= 10
    end
    nd = StrtodDecimal[d].nd
    i = 0
    while scale > 0
      return true if i >= nd

      digit = (p5 / scale) % 10
      if zr_strtod_digit(d, i) != digit
        return zr_strtod_digit(d, i) < digit
      end
      scale /= 10
      i += 1
    end
    false
  end

  # Multiplies by 2**k, k at most STRTOD_MAX_SHIFT (Go's leftShift).
  #: (ptr, word) -> void
  def zr_strtod_left_shift(d, k)
    # @type var quo: word
    # @type var rem: word
    # The new digits: those of 2**k, less one when the digits are below
    # 5**k.
    delta = 0
    p2 = 1 << k
    while p2 > 0
      delta += 1
      p2 /= 10
    end
    delta -= 1 if zr_strtod_below_pow5(d, k)
    nd = StrtodDecimal[d].nd
    r = nd - 1
    w = nd + delta
    n = 0
    while r >= 0
      n += zr_strtod_digit(d, r) << k
      quo = n / 10
      rem = n - (10 * quo)
      w -= 1
      if w < STRTOD_DIGITS
        zr_strtod_set_digit(d, w, rem)
      elsif rem != 0
        StrtodDecimal[d].trunc = 1
      end
      n = quo
      r -= 1
    end
    while n > 0
      quo = n / 10
      rem = n - (10 * quo)
      w -= 1
      if w < STRTOD_DIGITS
        zr_strtod_set_digit(d, w, rem)
      elsif rem != 0
        StrtodDecimal[d].trunc = 1
      end
      n = quo
    end
    nd += delta
    nd = STRTOD_DIGITS if nd >= STRTOD_DIGITS
    StrtodDecimal[d].nd = nd
    StrtodDecimal[d].dp = StrtodDecimal[d].dp + delta
    zr_strtod_trim(d)
  end

  # Multiplies by 2**k, or divides by 2**-k when k is negative (Go's
  # Shift).
  #: (ptr, word) -> void
  def zr_strtod_shift(d, k)
    return if StrtodDecimal[d].nd == 0

    if k > 0
      while k > STRTOD_MAX_SHIFT
        zr_strtod_left_shift(d, STRTOD_MAX_SHIFT)
        k -= STRTOD_MAX_SHIFT
      end
      zr_strtod_left_shift(d, k)
    elsif k < 0
      while k < -STRTOD_MAX_SHIFT
        zr_strtod_right_shift(d, STRTOD_MAX_SHIFT)
        k += STRTOD_MAX_SHIFT
      end
      zr_strtod_right_shift(d, -k)
    end
  end

  # Whether the digits after the first `n` round the integer of the
  # first `n` up: above half, or half and odd or truncated (Go's
  # shouldRoundUp).
  #: (ptr, word) -> bool
  def zr_strtod_round_up_p(d, n)
    nd = StrtodDecimal[d].nd
    return false if n < 0 || n >= nd

    if zr_strtod_digit(d, n) == 5 && n + 1 == nd
      return true if StrtodDecimal[d].trunc != 0

      return n > 0 && (zr_strtod_digit(d, n - 1) & 1) != 0
    end
    zr_strtod_digit(d, n) >= 5
  end

  # The integer part of `d`, rounded (Go's RoundedInteger). The caller
  # keeps it below 2**54.
  #: (ptr) -> word
  def zr_strtod_rounded_integer(d)
    dp = StrtodDecimal[d].dp
    nd = StrtodDecimal[d].nd
    n = 0
    i = 0
    while i < dp && i < nd
      n = (n * 10) + zr_strtod_digit(d, i)
      i += 1
    end
    while i < dp
      n *= 10
      i += 1
    end
    n += 1 if zr_strtod_round_up_p(d, dp)
    n
  end

  # The shift that Go's floatBits takes for a point `dp` digits away.
  #: (word) -> word
  def zr_strtod_powtab(dp)
    return 1 if dp == 0
    return 3 if dp == 1
    return 6 if dp == 2
    return 9 if dp == 3
    return 13 if dp == 4
    return 16 if dp == 5
    return 19 if dp == 6
    return 23 if dp == 7
    return 26 if dp == 8

    27
  end

  # The bits of the double nearest to `d`, without the sign (Go's
  # floatBits for float64).
  #: (ptr) -> word
  def zr_strtod_float_bits(d)
    # @type var n: word
    return 0 if StrtodDecimal[d].nd == 0
    return 0x7FF0000000000000 if StrtodDecimal[d].dp > 310
    return 0 if StrtodDecimal[d].dp < -330

    # Scale by powers of two into [0.5, 1).
    exp = 0
    while StrtodDecimal[d].dp > 0
      n = zr_strtod_powtab(StrtodDecimal[d].dp)
      zr_strtod_shift(d, -n)
      exp += n
    end
    while StrtodDecimal[d].dp < 0 || (StrtodDecimal[d].dp == 0 && zr_strtod_digit(d, 0) < 5)
      n = zr_strtod_powtab(-StrtodDecimal[d].dp)
      zr_strtod_shift(d, n)
      exp -= n
    end
    # The range is [0.5, 1), and a double's is [1, 2).
    exp -= 1
    # The least exponent is -1022; a smaller one makes a subnormal.
    if exp < -1022
      zr_strtod_shift(d, exp + 1022)
      exp = -1022
    end
    return 0x7FF0000000000000 if exp > 1023

    # The 53 bits of the mantissa.
    zr_strtod_shift(d, 53)
    mant = zr_strtod_rounded_integer(d)
    # The rounding can carry into a 54th bit.
    if mant == (1 << 53)
      mant >>= 1
      exp += 1
      return 0x7FF0000000000000 if exp > 1023
    end
    # Without the bit 52, the number is subnormal.
    return mant if (mant & (1 << 52)) == 0

    (mant & ((1 << 52) - 1)) | ((exp + 1023) << 52)
  end

  # A hex float at `s + i`, after its "0x" (musl's hexfloat). Keeps the
  # first 15 significant hex digits; a later digit that is not zero is
  # sticky for the rounding.
  #: (ptr, word, bool, ptr) -> f64
  def zr_strtod_hex(s, i, neg, stop)
    m = 0
    taken = 0
    e2 = 0
    sticky = false
    sawdot = false
    while true
      c = zr_strtod_at(s, i)
      v = zr_strtod_hex_value(c)
      if c == 46
        break if sawdot

        sawdot = true
      elsif v >= 0
        if m == 0 && v == 0
          e2 -= 4 if sawdot
        elsif taken < 15
          m = (m * 16) + v
          taken += 1
          e2 -= 4 if sawdot
        else
          sticky = true if v != 0
          e2 += 4 unless sawdot
        end
      else
        break
      end
      i += 1
    end
    if (zr_strtod_at(s, i) | 32) == 112
      j = i + 1
      esign = 1
      if zr_strtod_at(s, j) == 43
        j += 1
      elsif zr_strtod_at(s, j) == 45
        esign = -1
        j += 1
      end
      c = zr_strtod_at(s, j)
      if c >= 48 && c <= 57
        e = 0
        while c >= 48 && c <= 57
          e = (e * 10) + c - 48 if e < 100000
          j += 1
          c = zr_strtod_at(s, j)
        end
        e2 += esign * e
        i = j
      end
    end
    zr_strtod_stop(stop, s + i)
    zr_strtod_signed(zr_strtod_scale2(m, sticky, e2), neg)
  end

  # (m + a sticky fraction) * 2**e2, rounded once to a double. m is below
  # 2**60.
  #: (word, bool, word) -> f64
  def zr_strtod_scale2(m, sticky, e2)
    return Machine.f64(0) if m == 0

    top = e2 + 63 - Machine.clz(m)
    return Machine.f64(0x7FF0000000000000) if top > 1023

    # The exponent of the last bit that the double keeps.
    low = top - 52
    low = -1074 if low < -1074
    drop = low - e2
    if drop <= 0
      return ldexp(Machine.to_f64(m), Machine.i32(e2))
    end
    return Machine.f64(0) if drop > 61

    q = m >> drop
    rem = m & ((1 << drop) - 1)
    half = 1 << (drop - 1)
    q += 1 if rem > half || (rem == half && (sticky || (q & 1) != 0))
    ldexp(Machine.to_f64(q), Machine.i32(low))
  end
end
