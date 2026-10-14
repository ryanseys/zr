module Zr::Kern
  # The loops of bignum arithmetic (lib/zr/runtime/core/bignum.rb). A
  # magnitude is an Array of base-2^30 limbs, the lowest first, each a
  # fixnum.
  #
  # A def makes its result Array first, then reads its operands' limbs
  # where they are and writes each result limb, as a fixnum, past the
  # result's length. The collector does not move objects, and nothing
  # allocates in the loop, so the pointers hold. `zr_big_done` then sets
  # the length. Work that needs room for raw words (a product's sums, the
  # division's normalized operands) has a block of words that it frees.
  # BIG_BITS and BIG_MASK are in big_words.rb, with the long products.

  # `a + b`.
  #: (value, value) -> value
  def zr_big_add_mag(a, b)
    # @type var t: word
    if RArray[a].len < RArray[b].len
      return zr_big_add_mag(b, a)
    end
    n = RArray[a].len
    m = RArray[b].len
    out = zr_ary_new(n + 1)
    x = RArray[a].ptr
    y = RArray[b].ptr
    o = RArray[out].ptr
    carry = 0
    i = 0
    while i < m
      t = zr_big_at(x, i) + zr_big_at(y, i) + carry
      zr_big_put(o, i, t & BIG_MASK)
      carry = t >> BIG_BITS
      i += 1
    end
    while i < n
      t = zr_big_at(x, i) + carry
      zr_big_put(o, i, t & BIG_MASK)
      carry = t >> BIG_BITS
      i += 1
    end
    zr_big_put(o, n, carry)
    zr_big_done(out, n + 1)
  end

  # `a - b`, for `a >= b`. A limb's difference is above -2^30, so its low
  # 30 bits are the limb, and bit 30 is the borrow: no branch on it.
  #: (value, value) -> value
  def zr_big_sub_mag(a, b)
    # @type var t: word
    n = RArray[a].len
    m = RArray[b].len
    out = zr_ary_new(n)
    x = RArray[a].ptr
    y = RArray[b].ptr
    o = RArray[out].ptr
    borrow = 0
    i = 0
    while i < m
      t = zr_big_at(x, i) - zr_big_at(y, i) - borrow
      zr_big_put(o, i, t & BIG_MASK)
      borrow = (t >> BIG_BITS) & 1
      i += 1
    end
    while i < n
      t = zr_big_at(x, i) - borrow
      zr_big_put(o, i, t & BIG_MASK)
      borrow = (t >> BIG_BITS) & 1
      i += 1
    end
    zr_big_done(out, n)
  end

  # `a * b`, by the schoolbook method. A one-limb factor needs no sums,
  # and two long ones split by Karatsuba's (zr_big_kara).
  #: (value, value) -> value
  def zr_big_mul_mag(a, b)
    if RArray[a].len < RArray[b].len
      return zr_big_mul_mag(b, a)
    end
    n = RArray[a].len
    m = RArray[b].len
    out = zr_ary_new(n + m)
    if m == 0
      return out
    end
    x = RArray[a].ptr
    y = RArray[b].ptr
    if m == 1
      return zr_big_mul_word(out, a, zr_big_at(y, 0))
    end
    if m >= BIG_KARATSUBA
      return zr_big_mul_long(out, a, b)
    end
    sums = zr_big_zeros(n + m)
    i = 0
    while i < m
      yi = zr_big_at(y, i)
      carry = 0
      j = 0
      while j < n
        at = sums + ((i + j) * 8)
        t = Machine.load64(at, 0) + (yi * zr_big_at(x, j)) + carry
        Machine.store64(at, 0, t & BIG_MASK)
        carry = t >> BIG_BITS
        j += 1
      end
      Machine.store64(sums + ((i + n) * 8), 0, carry)
      i += 1
    end
    zr_big_fill(out, sums, n + m)
  end

  # Writes `a * b` into `out` for two long factors, `a` the longer: their
  # limbs as words, then Karatsuba's products (big_words.rb).
  #: (value, value, value) -> value
  def zr_big_mul_long(out, a, b)
    n = RArray[a].len
    m = RArray[b].len
    x = zr_big_words_of(a)
    y = zr_big_words_of(b)
    product = zr_xmalloc((n + m) * 8)
    work = zr_xmalloc(zr_big_kara_work(n) * 8)
    zr_big_kara(product, x, n, y, m, work)
    zr_xfree(work)
    zr_xfree(y)
    zr_xfree(x)
    zr_big_fill(out, product, n + m)
  end

  # A block of the limbs of the Array `a` as words. The caller frees it.
  #: (value) -> ptr
  def zr_big_words_of(a)
    n = RArray[a].len
    out = zr_xmalloc((n + 1) * 8)
    p = RArray[a].ptr
    i = 0
    while i < n
      Machine.store64(out + (i * 8), 0, zr_big_at(p, i))
      i += 1
    end
    out
  end

  # `a * m` for the fixnum `m`, at least zero and below 2^30.
  #: (value, value) -> value
  def zr_big_mul_small_mag(a, m)
    zr_big_mul_word(zr_ary_new(RArray[a].len + 1), a, zr_fix2long(m))
  end

  # Writes `a * f` into `out`, which has room for one limb more than `a`,
  # and returns it: one pass, with no sums.
  #: (value, value, word) -> value
  def zr_big_mul_word(out, a, f)
    n = RArray[a].len
    x = RArray[a].ptr
    o = RArray[out].ptr
    carry = 0
    i = 0
    while i < n
      t = (zr_big_at(x, i) * f) + carry
      zr_big_put(o, i, t & BIG_MASK)
      carry = t >> BIG_BITS
      i += 1
    end
    zr_big_put(o, n, carry)
    zr_big_done(out, n + 1)
  end

  # `[quotient, remainder]` of `a` by the fixnum `m`, which is above zero
  # and below 2^30. The remainder is a fixnum.
  #: (value, value) -> value
  def zr_big_divmod_small_mag(a, m)
    n = RArray[a].len
    out = zr_ary_new(2)
    q = zr_ary_new(n)
    zr_ary_push(out, q)
    x = RArray[a].ptr
    o = RArray[q].ptr
    d = zr_fix2long(m)
    rem = 0
    i = n
    while i > 0
      i -= 1
      t = (rem << BIG_BITS) + zr_big_at(x, i)
      zr_big_put(o, i, t / d)
      rem = t % d
    end
    zr_big_done(q, n)
    zr_ary_push(out, zr_fix(rem))
    out
  end

  # The digits of the magnitude `a` in `base`, which is not a power of
  # two, with zeros in front up to `width` digits and then a minus sign
  # when `neg` is true: a US-ASCII String. A word copy of the limbs is
  # divided in place by `chunk`, the largest power of the base below
  # 2^30, and each remainder gives `per` digits, the lowest first, into
  # one block that turns at the end. Each step reads only the words
  # still above zero, and nothing allocates in the loop.
  #: (value, value, value, value) -> value
  def zr_big_to_digits(a, base, neg, width)
    b = zr_fix2long(base)
    chunk = b
    per = 1
    while chunk * b <= BIG_MASK
      chunk *= b
      per += 1
    end
    n = RArray[a].len
    words = zr_big_words_of(a)
    # A chunk takes more than (bits of chunk - 1) bits off the value.
    room = ((((n * BIG_BITS) / (zr_big_word_bits(chunk) - 1)) + 1) * per) + 1
    w = zr_fix2long(width)
    if room <= w
      room = w + 1
    end
    text = zr_xmalloc(room)
    at = 0
    while n > 0
      rem = 0
      i = n
      while i > 0
        i -= 1
        t = (rem << BIG_BITS) + Machine.load64(words + (i * 8), 0)
        q = t / chunk
        Machine.store64(words + (i * 8), 0, q)
        rem = t - (q * chunk)
      end
      while n > 0 && Machine.load64(words + ((n - 1) * 8), 0) == 0
        n -= 1
      end
      k = 0
      while k < per && (n > 0 || rem > 0)
        d = rem % b
        Machine.store8(text + at, 0, Machine.i8(d < 10 ? 48 + d : 87 + d))
        rem /= b
        at += 1
        k += 1
      end
    end
    while at < w
      Machine.store8(text + at, 0, Machine.i8(48))
      at += 1
    end
    if neg == QTRUE
      Machine.store8(text + at, 0, Machine.i8(45))
      at += 1
    end
    zr_big_bytes_turn(text, at)
    s = zr_usascii_str_new(text, at)
    zr_xfree(text)
    zr_xfree(words)
    s
  end

  # Turns the `n` bytes at `p` end for end.
  #: (ptr, word) -> void
  def zr_big_bytes_turn(p, n)
    i = 0
    j = n - 1
    while i < j
      low = Machine.load8(p + i, 0)
      Machine.store8(p + i, 0, Machine.load8(p + j, 0))
      Machine.store8(p + j, 0, low)
      i += 1
      j -= 1
    end
  end

  # Knuth's algorithm D: `[quotient, remainder]` of `a` by `b`, for a
  # divisor of two limbs or more and `a >= b`.
  #: (value, value) -> value
  def zr_big_divmod_mag(a, b)
    size = RArray[a].len
    n = RArray[b].len
    m = size - n
    out = zr_ary_new(2)
    quotient = zr_ary_new(m + 1)
    zr_ary_push(out, quotient)
    remainder = zr_ary_new(n)
    zr_ary_push(out, remainder)
    # Shifts both so the divisor's top limb has its top bit set.
    s = BIG_BITS - zr_big_word_bits(zr_big_at(RArray[b].ptr, n - 1))
    u = zr_big_shifted_words(a, s)
    v = zr_big_shifted_words(b, s)
    q = RArray[quotient].ptr
    vtop = Machine.load64(v + ((n - 1) * 8), 0)
    vsec = Machine.load64(v + ((n - 2) * 8), 0)
    j = m + 1
    while j > 0
      j -= 1
      num = (Machine.load64(u + ((j + n) * 8), 0) << BIG_BITS) + Machine.load64(u + ((j + n - 1) * 8), 0)
      qhat = num / vtop
      rhat = num % vtop
      while rhat <= BIG_MASK && (qhat > BIG_MASK || qhat * vsec > (rhat << BIG_BITS) + Machine.load64(u + ((j + n - 2) * 8), 0))
        qhat -= 1
        rhat += vtop
      end
      borrow = 0
      carry = 0
      i = 0
      while i < n
        p = (qhat * Machine.load64(v + (i * 8), 0)) + carry
        carry = p >> BIG_BITS
        t = Machine.load64(u + ((i + j) * 8), 0) - (p & BIG_MASK) - borrow
        Machine.store64(u + ((i + j) * 8), 0, t & BIG_MASK)
        borrow = (t >> BIG_BITS) & 1
        i += 1
      end
      t = Machine.load64(u + ((j + n) * 8), 0) - carry - borrow
      if t < 0
        # qhat was one too large: add the divisor back.
        Machine.store64(u + ((j + n) * 8), 0, t + BIG_MASK + 1)
        qhat -= 1
        carry = 0
        i = 0
        while i < n
          t = Machine.load64(u + ((i + j) * 8), 0) + Machine.load64(v + (i * 8), 0) + carry
          Machine.store64(u + ((i + j) * 8), 0, t & BIG_MASK)
          carry = t >> BIG_BITS
          i += 1
        end
        Machine.store64(u + ((j + n) * 8), 0, (Machine.load64(u + ((j + n) * 8), 0) + carry) & BIG_MASK)
      else
        Machine.store64(u + ((j + n) * 8), 0, t)
      end
      zr_big_put(q, j, qhat)
    end
    zr_big_done(quotient, m + 1)
    zr_xfree(v)
    # The remainder is the low `n` limbs of `u`, shifted back.
    r = RArray[remainder].ptr
    i = 0
    while i < n
      high = i + 1 < n ? Machine.load64(u + ((i + 1) * 8), 0) : 0
      zr_big_put(r, i, (Machine.load64(u + (i * 8), 0) >> s) | ((high << (BIG_BITS - s)) & BIG_MASK))
      i += 1
    end
    zr_xfree(u)
    zr_big_done(remainder, n)
    out
  end

  # -1, 0 or 1 as `a` is below, equal to or above `b`.
  #: (value, value) -> value
  def zr_big_cmp_mag(a, b)
    n = RArray[a].len
    if n != RArray[b].len
      return zr_fix(n < RArray[b].len ? 0 - 1 : 1)
    end
    x = RArray[a].ptr
    y = RArray[b].ptr
    i = n
    while i > 0
      i -= 1
      p = zr_big_at(x, i)
      r = zr_big_at(y, i)
      if p != r
        return zr_fix(p < r ? 0 - 1 : 1)
      end
    end
    zr_fix(0)
  end

  # The limb at `i` of the Array elements at `p`.
  #: (ptr, word) -> word
  def zr_big_at(p, i)
    Machine.load64(p + (i * 8), 0) >> 1
  end

  # Writes the limb `w` as a fixnum at `i` of the Array elements at `p`.
  #: (ptr, word, word) -> void
  def zr_big_put(p, i, w)
    Machine.store64(p + (i * 8), 0, (w << 1) | 1)
  end

  # Gives `out` the first `n` limbs written to it, without the zero limbs
  # on top, and returns it.
  #: (value, word) -> value
  def zr_big_done(out, n)
    p = RArray[out].ptr
    while n > 0 && Machine.load64(p + ((n - 1) * 8), 0) == 1
      n -= 1
    end
    RArray[out].len = n
    out
  end

  # Writes the `n` words at `words` to `out` as limbs, frees `words`,
  # and gives `out` its length.
  #: (value, ptr, word) -> value
  def zr_big_fill(out, words, n)
    o = RArray[out].ptr
    i = 0
    while i < n
      zr_big_put(o, i, Machine.load64(words + (i * 8), 0))
      i += 1
    end
    zr_xfree(words)
    zr_big_done(out, n)
  end

  # A block of the limbs of the Array `a` shifted left by `s` bits (below
  # 30), as words, and one word on top with the bits that come up. One
  # pass: the division's normalized operands. The caller frees it.
  #: (value, word) -> ptr
  def zr_big_shifted_words(a, s)
    n = RArray[a].len
    out = zr_xmalloc((n + 1) * 8)
    p = RArray[a].ptr
    low = 0
    i = 0
    while i < n
      w = zr_big_at(p, i)
      Machine.store64(out + (i * 8), 0, ((w << s) | (low >> (BIG_BITS - s))) & BIG_MASK)
      low = w
      i += 1
    end
    Machine.store64(out + (n * 8), 0, low >> (BIG_BITS - s))
    out
  end

  # A block of `n` zero words, at least one. The caller frees it.
  #: (word) -> ptr
  def zr_big_zeros(n)
    out = zr_xmalloc((n + 1) * 8)
    i = 0
    while i <= n
      Machine.store64(out + (i * 8), 0, 0)
      i += 1
    end
    out
  end

  # The bits of `w` (above zero) up to its top set bit.
  #: (word) -> word
  def zr_big_word_bits(w)
    bits = 0
    while w > 0
      w >>= 1
      bits += 1
    end
    bits
  end
end
