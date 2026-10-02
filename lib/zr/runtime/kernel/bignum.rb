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
  BIG_BITS = 30
  BIG_MASK = 1073741823

  # `a + b`.
  sig [Value, Value] => Value
  def zr_big_add_mag(a, b)
    if RArray.len(a) < RArray.len(b)
      return zr_big_add_mag(b, a)
    end
    n = RArray.len(a)
    m = RArray.len(b)
    out = zr_ary_new(n + 1)
    x = RArray.ptr(a)
    y = RArray.ptr(b)
    o = RArray.ptr(out)
    carry = 0
    i = 0
    while i < n
      t = zr_big_at(x, i) + (i < m ? zr_big_at(y, i) : 0) + carry
      zr_big_put(o, i, t & BIG_MASK)
      carry = t >> BIG_BITS
      i += 1
    end
    zr_big_put(o, n, carry)
    zr_big_done(out, n + 1)
  end

  # `a - b`, for `a >= b`.
  sig [Value, Value] => Value
  def zr_big_sub_mag(a, b)
    n = RArray.len(a)
    m = RArray.len(b)
    out = zr_ary_new(n)
    x = RArray.ptr(a)
    y = RArray.ptr(b)
    o = RArray.ptr(out)
    borrow = 0
    i = 0
    while i < n
      t = zr_big_at(x, i) - (i < m ? zr_big_at(y, i) : 0) - borrow
      if t < 0
        t += BIG_MASK + 1
        borrow = 1
      else
        borrow = 0
      end
      zr_big_put(o, i, t)
      i += 1
    end
    zr_big_done(out, n)
  end

  # `a * b`, by the schoolbook method. A one-limb factor needs no sums.
  sig [Value, Value] => Value
  def zr_big_mul_mag(a, b)
    if RArray.len(a) < RArray.len(b)
      return zr_big_mul_mag(b, a)
    end
    n = RArray.len(a)
    m = RArray.len(b)
    out = zr_ary_new(n + m)
    if m == 0
      return out
    end
    x = RArray.ptr(a)
    y = RArray.ptr(b)
    if m == 1
      f = zr_big_at(y, 0)
      o = RArray.ptr(out)
      carry = 0
      i = 0
      while i < n
        t = (zr_big_at(x, i) * f) + carry
        zr_big_put(o, i, t & BIG_MASK)
        carry = t >> BIG_BITS
        i += 1
      end
      zr_big_put(o, n, carry)
      return zr_big_done(out, n + 1)
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

  # `[quotient, remainder]` of `a` by the fixnum `m`, which is above zero
  # and below 2^30. The remainder is a fixnum.
  sig [Value, Value] => Value
  def zr_big_divmod_small_mag(a, m)
    n = RArray.len(a)
    out = zr_ary_new(2)
    q = zr_ary_new(n)
    zr_ary_push(out, q)
    x = RArray.ptr(a)
    o = RArray.ptr(q)
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

  # Knuth's algorithm D: `[quotient, remainder]` of `a` by `b`, for a
  # divisor of two limbs or more and `a >= b`.
  sig [Value, Value] => Value
  def zr_big_divmod_mag(a, b)
    size = RArray.len(a)
    n = RArray.len(b)
    m = size - n
    out = zr_ary_new(2)
    quotient = zr_ary_new(m + 1)
    zr_ary_push(out, quotient)
    remainder = zr_ary_new(n)
    zr_ary_push(out, remainder)
    u = zr_big_words(a, 1)
    v = zr_big_words(b, 0)
    # Shifts both so the divisor's top limb has its top bit set.
    s = BIG_BITS - zr_big_word_bits(Machine.load64(v + ((n - 1) * 8), 0))
    zr_big_shl_words(u, size + 1, s)
    zr_big_shl_words(v, n, s)
    q = RArray.ptr(quotient)
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
        if t < 0
          t += BIG_MASK + 1
          borrow = 1
        else
          borrow = 0
        end
        Machine.store64(u + ((i + j) * 8), 0, t)
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
    r = RArray.ptr(remainder)
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
  sig [Value, Value] => Value
  def zr_big_cmp_mag(a, b)
    n = RArray.len(a)
    if n != RArray.len(b)
      return zr_fix(n < RArray.len(b) ? 0 - 1 : 1)
    end
    x = RArray.ptr(a)
    y = RArray.ptr(b)
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
  sig [Ptr, Word] => Word
  def zr_big_at(p, i)
    Machine.load64(p + (i * 8), 0) >> 1
  end

  # Writes the limb `w` as a fixnum at `i` of the Array elements at `p`.
  sig [Ptr, Word, Word] => Void
  def zr_big_put(p, i, w)
    Machine.store64(p + (i * 8), 0, (w << 1) | 1)
  end

  # Gives `out` the first `n` limbs written to it, without the zero limbs
  # on top, and returns it.
  sig [Value, Word] => Value
  def zr_big_done(out, n)
    p = RArray.ptr(out)
    while n > 0 && Machine.load64(p + ((n - 1) * 8), 0) == 1
      n -= 1
    end
    RArray.set_len(out, n)
    out
  end

  # Writes the `n` words at `words` to `out` as limbs, frees `words`,
  # and gives `out` its length.
  sig [Value, Ptr, Word] => Value
  def zr_big_fill(out, words, n)
    o = RArray.ptr(out)
    i = 0
    while i < n
      zr_big_put(o, i, Machine.load64(words + (i * 8), 0))
      i += 1
    end
    zr_xfree(words)
    zr_big_done(out, n)
  end

  # A block of the limbs of the Array `a` as words, then `extra` zero
  # words. The caller frees it.
  sig [Value, Word] => Ptr
  def zr_big_words(a, extra)
    n = RArray.len(a)
    out = zr_big_zeros(n + extra)
    p = RArray.ptr(a)
    i = 0
    while i < n
      Machine.store64(out + (i * 8), 0, zr_big_at(p, i))
      i += 1
    end
    out
  end

  # A block of `n` zero words, at least one. The caller frees it.
  sig [Word] => Ptr
  def zr_big_zeros(n)
    out = zr_xmalloc((n + 1) * 8)
    i = 0
    while i <= n
      Machine.store64(out + (i * 8), 0, 0)
      i += 1
    end
    out
  end

  # Shifts the `n` limbs at `words` left by `s` bits (below 30) in place.
  # The top limb must have room for the bits that come up.
  sig [Ptr, Word, Word] => Void
  def zr_big_shl_words(words, n, s)
    i = n - 1
    while i > 0
      low = Machine.load64(words + ((i - 1) * 8), 0)
      Machine.store64(words + (i * 8), 0, ((Machine.load64(words + (i * 8), 0) << s) | (low >> (BIG_BITS - s))) & BIG_MASK)
      i -= 1
    end
    Machine.store64(words, 0, (Machine.load64(words, 0) << s) & BIG_MASK)
  end

  # The bits of `w` (above zero) up to its top set bit.
  sig [Word] => Word
  def zr_big_word_bits(w)
    bits = 0
    while w > 0
      w >>= 1
      bits += 1
    end
    bits
  end
end
