module Zr::Kern
  # zlib's checksums: adler32.c and crc32.c, as in zlib 1.3.1. A sum is a
  # 32-bit value in a Word. The C unsigned long is 64 bits on each host
  # that zr builds for, so no calculation here overflows where the C does
  # not. Derived from zlib; the license is in lib/zr/runtime/kernel/zlib.rb.
  ADLER_BASE = 65521
  ADLER_NMAX = 5552
  CRC_POLY = 3988292384
  ZLIB_MASK32 = 4294967295

  # adler32_z: updates `adler` with the `len` bytes at `buf`. A null buffer
  # returns the initial value, 1. A single byte uses a short path first,
  # as in the C, which keeps it fast for a caller that adds one byte at a
  # time.
  #: (word, ptr, word) -> word
  def zr_adler32(adler, buf, len)
    sum2 = (adler >> 16) & 65535
    adler = adler & 65535
    if len == 1
      adler += Machine.u8(Machine.load8(buf, 0))
      if adler >= ADLER_BASE
        adler -= ADLER_BASE
      end
      sum2 += adler
      if sum2 >= ADLER_BASE
        sum2 -= ADLER_BASE
      end
      return adler | (sum2 << 16)
    end
    if buf == 0
      return 1
    end
    if len < 16
      while len > 0
        len -= 1
        adler += Machine.u8(Machine.load8(buf, 0))
        buf += 1
        sum2 += adler
      end
      if adler >= ADLER_BASE
        adler -= ADLER_BASE
      end
      sum2 = sum2 % ADLER_BASE
      return adler | (sum2 << 16)
    end
    while len >= ADLER_NMAX
      len -= ADLER_NMAX
      n = ADLER_NMAX
      while n > 0
        n -= 1
        adler += Machine.u8(Machine.load8(buf, 0))
        buf += 1
        sum2 += adler
      end
      adler = adler % ADLER_BASE
      sum2 = sum2 % ADLER_BASE
    end
    if len > 0
      while len > 0
        len -= 1
        adler += Machine.u8(Machine.load8(buf, 0))
        buf += 1
        sum2 += adler
      end
      adler = adler % ADLER_BASE
      sum2 = sum2 % ADLER_BASE
    end
    adler | (sum2 << 16)
  end

  # adler32_combine_: the sum of two buffers, from their sums and the
  # length of the second buffer. A negative length returns an invalid sum,
  # as the C does, to show the error.
  #: (word, word, word) -> word
  def zr_adler32_combine(adler1, adler2, len2)
    if len2 < 0
      return ZLIB_MASK32
    end
    rem = len2 % ADLER_BASE
    sum1 = adler1 & 65535
    sum2 = (rem * sum1) % ADLER_BASE
    sum1 += (adler2 & 65535) + ADLER_BASE - 1
    sum2 += ((adler1 >> 16) & 65535) + ((adler2 >> 16) & 65535) + ADLER_BASE - rem
    if sum1 >= ADLER_BASE
      sum1 -= ADLER_BASE
    end
    if sum1 >= ADLER_BASE
      sum1 -= ADLER_BASE
    end
    if sum2 >= ADLER_BASE * 2
      sum2 -= ADLER_BASE * 2
    end
    if sum2 >= ADLER_BASE
      sum2 -= ADLER_BASE
    end
    sum1 | (sum2 << 16)
  end

  # crc32_z: updates `crc` with the `len` bytes at `buf`, one byte at a
  # time through the table. The braided and hardware paths of the C give
  # the same bits. A null buffer returns the initial value, 0.
  #: (word, ptr, word) -> word
  def zr_crc32(crc, buf, len)
    if buf == 0
      return 0
    end
    table = zr_crc_table()
    crc = (crc ^ ZLIB_MASK32) & ZLIB_MASK32
    while len > 0
      len -= 1
      crc = (crc >> 8) ^ Machine.u32(Machine.load32(table + (((crc ^ Machine.u8(Machine.load8(buf, 0))) & 255) * 4), 0))
      buf += 1
    end
    crc ^ ZLIB_MASK32
  end

  # multmodp: a(x) times b(x) modulo p(x), the CRC polynomial reflected.
  # `a` must not be zero, as the C requires.
  #: (word, word) -> word
  def zr_crc_multmodp(a, b)
    m = 2147483648
    p = 0
    while true
      if (a & m) != 0
        p = p ^ b
        if (a & (m - 1)) == 0
          break
        end
      end
      m = m >> 1
      if (b & 1) != 0
        b = (b >> 1) ^ CRC_POLY
      else
        b = b >> 1
      end
    end
    p
  end

  # x2nmodp: x^(n * 2^k) modulo p(x). A negative `n` never gets to zero,
  # the same as in the C.
  #: (word, word) -> word
  def zr_crc_x2nmodp(n, k)
    table = zr_crc_x2n_table()
    p = 2147483648
    while n != 0
      if (n & 1) != 0
        p = zr_crc_multmodp(Machine.u32(Machine.load32(table + ((k & 31) * 4), 0)), p)
      end
      n = n >> 1
      k += 1
    end
    p
  end

  # crc32_combine64: the CRC of two buffers, from their CRCs and the
  # length of the second buffer.
  #: (word, word, word) -> word
  def zr_crc32_combine(crc1, crc2, len2)
    zr_crc_multmodp(zr_crc_x2nmodp(len2, 3), crc1 & ZLIB_MASK32) ^ (crc2 & ZLIB_MASK32)
  end
end
