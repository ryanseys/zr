module Zr::Kern
  # Bignum products over raw words: a block of words, each a limb below
  # 2^30, the lowest first, with no fixnum tag. zr_big_mul_mag
  # (bignum.rb) copies its operands' limbs into such blocks for a long
  # product, so the work here reads and writes words and allocates
  # nothing. A limb's product is below 2^60, so a word holds it with a
  # sum and a carry.
  BIG_BITS = 30
  BIG_MASK = 1073741823

  # The length of the shorter factor from which a product splits by
  # Karatsuba's method; below it, the schoolbook is faster.
  BIG_KARATSUBA = 32

  # The words of the work block that zr_big_kara needs for a longer
  # factor of `n` words: each split takes about 2n words, and the next
  # one takes half as many again.
  #: (word) -> word
  def zr_big_kara_work(n)
    (8 * n) + 256
  end

  # `r = x * y` for `x` of `n` words and `y` of `m`, `n >= m >= 1`. `r`
  # has room for n + m words; `work` has zr_big_kara_work(n). A factor
  # shorter than BIG_KARATSUBA takes the schoolbook. Otherwise, with `h`
  # half of `x`: a `y` no longer than `h` takes two products, by the two
  # halves of `x`; a longer one splits too, and the three products are
  # x0*y0, x1*y1 and (x0 + x1)(y0 + y1), from which the middle term is
  # the difference.
  #: (ptr, ptr, word, ptr, word, ptr) -> void
  def zr_big_kara(r, x, n, y, m, work)
    if m < BIG_KARATSUBA
      zr_big_school(r, x, n, y, m)
      return
    end
    h = (n + 1) / 2
    if m <= h
      zr_big_kara(r, x, h, y, m, work)
      high = work
      zr_big_mul_words(high, x + (h * 8), n - h, y, m, work + ((n - h + m) * 8))
      zr_big_words_zero(r + ((h + m) * 8), n - h)
      zr_big_words_add(r + (h * 8), high, n - h + m)
      return
    end
    zr_big_kara(r, x, h, y, h, work)
    zr_big_mul_words(r + (2 * h * 8), x + (h * 8), n - h, y + (h * 8), m - h, work)
    xs = work
    ys = work + ((h + 1) * 8)
    middle = work + (2 * (h + 1) * 8)
    zr_big_words_sum(xs, x, h, x + (h * 8), n - h)
    zr_big_words_sum(ys, y, h, y + (h * 8), m - h)
    zr_big_kara(middle, xs, h + 1, ys, h + 1, middle + (2 * (h + 1) * 8))
    zr_big_words_sub(middle, r, 2 * h)
    zr_big_words_sub(middle, r + (2 * h * 8), n + m - (2 * h))
    # The middle term fits the words above `h`; its words past them are
    # zero.
    span = 2 * (h + 1)
    if span > n + m - h
      span = n + m - h
    end
    zr_big_words_add(r + (h * 8), middle, span)
  end

  # zr_big_kara for factors in either order.
  #: (ptr, ptr, word, ptr, word, ptr) -> void
  def zr_big_mul_words(r, a, an, b, bn, work)
    if an >= bn
      zr_big_kara(r, a, an, b, bn, work)
    else
      zr_big_kara(r, b, bn, a, an, work)
    end
  end

  # `r = x * y` by the schoolbook: one row of sums for each word of `y`.
  #: (ptr, ptr, word, ptr, word) -> void
  def zr_big_school(r, x, n, y, m)
    zr_big_words_zero(r, n)
    i = 0
    while i < m
      yi = Machine.load64(y + (i * 8), 0)
      carry = 0
      j = 0
      while j < n
        at = r + ((i + j) * 8)
        t = Machine.load64(at, 0) + (yi * Machine.load64(x + (j * 8), 0)) + carry
        Machine.store64(at, 0, t & BIG_MASK)
        carry = t >> BIG_BITS
        j += 1
      end
      Machine.store64(r + ((i + n) * 8), 0, carry)
      i += 1
    end
  end

  # `out = a + b` for `a` of `an` words and `b` of `bn`, `an >= bn`: an
  # + 1 words, the last one the carry.
  #: (ptr, ptr, word, ptr, word) -> void
  def zr_big_words_sum(out, a, an, b, bn)
    carry = 0
    i = 0
    while i < an
      t = Machine.load64(a + (i * 8), 0) + carry
      if i < bn
        t += Machine.load64(b + (i * 8), 0)
      end
      Machine.store64(out + (i * 8), 0, t & BIG_MASK)
      carry = t >> BIG_BITS
      i += 1
    end
    Machine.store64(out + (an * 8), 0, carry)
  end

  # `r += a` for `a` of `n` words. The carry goes up through `r`, which
  # has room for the sum.
  #: (ptr, ptr, word) -> void
  def zr_big_words_add(r, a, n)
    carry = 0
    i = 0
    while i < n || carry != 0
      t = Machine.load64(r + (i * 8), 0) + carry
      if i < n
        t += Machine.load64(a + (i * 8), 0)
      end
      Machine.store64(r + (i * 8), 0, t & BIG_MASK)
      carry = t >> BIG_BITS
      i += 1
    end
  end

  # `r -= a` for `a` of `n` words, `r >= a`. The borrow goes up through
  # `r`. A word's difference is above -2^30, so its low 30 bits are the
  # word, and bit 30 is the borrow.
  #: (ptr, ptr, word) -> void
  def zr_big_words_sub(r, a, n)
    borrow = 0
    i = 0
    while i < n || borrow != 0
      t = Machine.load64(r + (i * 8), 0) - borrow
      if i < n
        t -= Machine.load64(a + (i * 8), 0)
      end
      Machine.store64(r + (i * 8), 0, t & BIG_MASK)
      borrow = (t >> BIG_BITS) & 1
      i += 1
    end
  end

  # Zeros the `n` words at `p`.
  #: (ptr, word) -> void
  def zr_big_words_zero(p, n)
    i = 0
    while i < n
      Machine.store64(p + (i * 8), 0, 0)
      i += 1
    end
  end
end
