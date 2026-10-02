module Zr::Kern
  # The loops of bignum arithmetic (lib/zr/runtime/core/bignum.rb). A
  # magnitude is an Array of base-2^30 limbs, the lowest first, each a
  # fixnum. Each def copies its operands' limbs to a block of words, does
  # its work there, and makes its result Arrays last, so no collection
  # runs while it holds a pointer into an Array.
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
    x = zr_big_words(a, 1)
    y = zr_big_words(b, 0)
    carry = 0
    i = 0
    while i < n
      t = Machine.load64(x + (i * 8), 0) + (i < m ? Machine.load64(y + (i * 8), 0) : 0) + carry
      Machine.store64(x + (i * 8), 0, t & BIG_MASK)
      carry = t >> BIG_BITS
      i += 1
    end
    Machine.store64(x + (n * 8), 0, carry)
    zr_xfree(y)
    zr_big_limbs(x, n + 1)
  end

  # `a - b`, for `a >= b`.
  sig [Value, Value] => Value
  def zr_big_sub_mag(a, b)
    n = RArray.len(a)
    m = RArray.len(b)
    x = zr_big_words(a, 0)
    y = zr_big_words(b, 0)
    borrow = 0
    i = 0
    while i < n
      t = Machine.load64(x + (i * 8), 0) - (i < m ? Machine.load64(y + (i * 8), 0) : 0) - borrow
      if t < 0
        t += BIG_MASK + 1
        borrow = 1
      else
        borrow = 0
      end
      Machine.store64(x + (i * 8), 0, t)
      i += 1
    end
    zr_xfree(y)
    zr_big_limbs(x, n)
  end

  # `a * b`, by the schoolbook method.
  sig [Value, Value] => Value
  def zr_big_mul_mag(a, b)
    n = RArray.len(a)
    m = RArray.len(b)
    x = zr_big_words(a, 0)
    y = zr_big_words(b, 0)
    out = zr_big_zeros(n + m)
    i = 0
    while i < n
      xi = Machine.load64(x + (i * 8), 0)
      carry = 0
      j = 0
      while j < m
        at = out + ((i + j) * 8)
        t = Machine.load64(at, 0) + (xi * Machine.load64(y + (j * 8), 0)) + carry
        Machine.store64(at, 0, t & BIG_MASK)
        carry = t >> BIG_BITS
        j += 1
      end
      Machine.store64(out + ((i + m) * 8), 0, Machine.load64(out + ((i + m) * 8), 0) + carry)
      i += 1
    end
    zr_xfree(x)
    zr_xfree(y)
    zr_big_limbs(out, n + m)
  end

  # `[quotient, remainder]` of `a` by the fixnum `m`, which is above zero
  # and below 2^30. The remainder is a fixnum.
  sig [Value, Value] => Value
  def zr_big_divmod_small_mag(a, m)
    n = RArray.len(a)
    x = zr_big_words(a, 0)
    d = zr_fix2long(m)
    rem = 0
    i = n
    while i > 0
      i -= 1
      t = (rem << BIG_BITS) + Machine.load64(x + (i * 8), 0)
      Machine.store64(x + (i * 8), 0, t / d)
      rem = t % d
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_big_limbs(x, n))
    zr_ary_push(out, zr_fix(rem))
    out
  end

  # Knuth's algorithm D: `[quotient, remainder]` of `a` by `b`, for a
  # divisor of two limbs or more and `a >= b`.
  sig [Value, Value] => Value
  def zr_big_divmod_mag(a, b)
    size = RArray.len(a)
    n = RArray.len(b)
    u = zr_big_words(a, 1)
    v = zr_big_words(b, 0)
    # Shifts both so the divisor's top limb has its top bit set.
    s = BIG_BITS - zr_big_word_bits(Machine.load64(v + ((n - 1) * 8), 0))
    zr_big_shl_words(u, size + 1, s)
    zr_big_shl_words(v, n, s)
    m = size - n
    q = zr_big_zeros(m + 1)
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
      Machine.store64(q + (j * 8), 0, qhat)
    end
    zr_xfree(v)
    # The remainder is the low `n` limbs of `u`, shifted back.
    i = 0
    while i < n
      high = i + 1 < n ? Machine.load64(u + ((i + 1) * 8), 0) : 0
      Machine.store64(u + (i * 8), 0, (Machine.load64(u + (i * 8), 0) >> s) | ((high << (BIG_BITS - s)) & BIG_MASK))
      i += 1
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_big_limbs(q, m + 1))
    zr_ary_push(out, zr_big_limbs(u, n))
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
      p = Machine.load64(x + (i * 8), 0)
      r = Machine.load64(y + (i * 8), 0)
      if p != r
        return zr_fix(p < r ? 0 - 1 : 1)
      end
    end
    zr_fix(0)
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
      Machine.store64(out + (i * 8), 0, zr_fix2long(Machine.value(Machine.load64(p + (i * 8), 0))))
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

  # An Array of the first `n` words of `words` without the zero words on
  # top. Frees `words`.
  sig [Ptr, Word] => Value
  def zr_big_limbs(words, n)
    while n > 0 && Machine.load64(words + ((n - 1) * 8), 0) == 0
      n -= 1
    end
    out = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(out, zr_fix(Machine.load64(words + (i * 8), 0)))
      i += 1
    end
    zr_xfree(words)
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
