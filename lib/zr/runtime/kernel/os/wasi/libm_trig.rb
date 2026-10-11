# sin, cos and tan, ported from musl 1.2.5's sin.c, cos.c, tan.c, __sin.c,
# __cos.c, __rem_pio2.c and __rem_pio2_large.c (from FreeBSD; Copyright
# (C) 1993 by Sun Microsystems, Inc.) and __tan.c (Copyright 2004 Sun
# Microsystems, Inc.). See THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # The double `i` of the array at `p`.
  #: (ptr, word) -> f64
  def zr_libm_at(p, i)
    Machine.f64(Machine.load64(p + (i * 8), 0))
  end

  # Stores `v` as the double `i` of the array at `p`.
  #: (ptr, word, f64) -> void
  def zr_libm_put(p, i, v)
    Machine.store64(p + (i * 8), 0, Machine.bits(v))
  end

  # sin(x + y) on [-pi/4, pi/4], with y the tail of x; `iy` is 0 when y
  # is 0 (__sin).
  #: (f64, f64, word) -> f64
  def zr_libm_k_sin(x, y, iy)
    s1 = Machine.f64(Machine.word(0xBFC5555555555549))
    z = x * x
    w = z * z
    r = Machine.f64(0x3F8111111110F8A6) + (z * (Machine.f64(Machine.word(0xBF2A01A019C161D5)) + (z * Machine.f64(0x3EC71DE357B1FE7D)))) +
        (z * w * (Machine.f64(Machine.word(0xBE5AE5E68A2B9CEB)) + (z * Machine.f64(0x3DE5D93A5ACFD57C))))
    v = z * x
    return x + (v * (s1 + (z * r))) if iy == 0

    x - (((z * ((Machine.f64(0x3FE0000000000000) * y) - (v * r))) - y) - (v * s1))
  end

  # cos(x + y) on [-pi/4, pi/4], with y the tail of x (__cos).
  #: (f64, f64) -> f64
  def zr_libm_k_cos(x, y)
    one = Machine.f64(0x3FF0000000000000)
    z = x * x
    w = z * z
    r = (z * (Machine.f64(0x3FA555555555554C) + (z * (Machine.f64(Machine.word(0xBF56C16C16C15177)) + (z * Machine.f64(0x3EFA01A019CB1590)))))) +
        (w * w * (Machine.f64(Machine.word(0xBE927E4F809C52AD)) +
                  (z * (Machine.f64(0x3E21EE9EBDB4B1C4) + (z * Machine.f64(Machine.word(0xBDA8FAE9BE8838D4)))))))
    hz = Machine.f64(0x3FE0000000000000) * z
    w = one - hz
    w + (((one - w) - hz) + ((z * r) - (x * y)))
  end

  # tan(x + y) on [-pi/4, pi/4], with y the tail of x; -1/tan when `odd`
  # is 1 (__tan).
  #: (f64, f64, word) -> f64
  def zr_libm_k_tan(x, y, odd)
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    hx = zr_libm_high(x)
    # |x| >= 0.6744
    big = (hx & 0x7FFFFFFF) >= 0x3FE59428
    sign = hx >> 31
    if big
      if sign != 0
        x = -x
        y = -y
      end
      x = (Machine.f64(0x3FE921FB54442D18) - x) + (Machine.f64(0x3C81A62633145C07) - y) # pio4, pio4lo
      y = Machine.f64(0)
    end
    z = x * x
    w = z * z
    # x**5*(T[1]+x**2*T[2]+...) as x**5(T[1]+x**4*T[3]+...+x**20*T[11]) +
    # x**5(x**2*(T[2]+x**4*T[4]+...+x**22*[T12])).
    # r = T[1] + w*(T[3] + w*(T[5] + w*(T[7] + w*(T[9] + w*T[11]))))
    r = Machine.f64(0x3F147E88A03792A6) + (w * Machine.f64(Machine.word(0xBEF375CBDB605373)))
    r = Machine.f64(0x3F4344D8F2F26501) + (w * r)
    r = Machine.f64(0x3F6D6D22C9560328) + (w * r)
    r = Machine.f64(0x3F9664F48406D637) + (w * r)
    r = Machine.f64(0x3FC111111110FE7A) + (w * r)
    # v = z*(T[2] + w*(T[4] + w*(T[6] + w*(T[8] + w*(T[10] + w*T[12])))))
    v = Machine.f64(0x3F12B80F32F0A7E9) + (w * Machine.f64(0x3EFB2A7074BF7AD4))
    v = Machine.f64(0x3F3026F71A8D1068) + (w * v)
    v = Machine.f64(0x3F57DBC8FEE08315) + (w * v)
    v = Machine.f64(0x3F8226E3E96E8493) + (w * v)
    v = z * (Machine.f64(0x3FABA1BA1BB341FE) + (w * v))
    s = z * x
    r = y + (z * ((s * (r + v)) + y)) + (s * Machine.f64(0x3FD5555555555563))
    w = x + r
    if big
      s = one - (two * Machine.to_f64(odd))
      v = s - (two * (x + (r - (w * w / (w + s)))))
      return sign != 0 ? -v : v
    end
    return w if odd == 0

    # -1.0/(x+r) has an error of up to 2 ulp, so compute it precisely.
    w0 = zr_libm_with_low(w, 0)
    # w0+v = r+x
    v = r - (w0 - x)
    a = -one / w
    a0 = zr_libm_with_low(a, 0)
    a0 + (a * (one + (a0 * w0) + (a0 * v)))
  end

  # x - n*pi/2 as y[0] + y[1] at `y`, for |x| ~<= 9pi/4 in an easy case:
  # n is `k`, or -`k` for a negative x.
  #: (f64, ptr, word, bool) -> word
  def zr_libm_rem_pio2_near(x, y, k, neg)
    kd = Machine.to_f64(k)
    pio2 = kd * Machine.f64(0x3FF921FB54400000) # k*pio2_1
    tail = kd * Machine.f64(0x3DD0B4611A626331) # k*pio2_1t
    if neg
      z = x + pio2
      y0 = z + tail
      zr_libm_put(y, 0, y0)
      zr_libm_put(y, 1, (z - y0) + tail)
      return -k
    end
    z = x - pio2
    y0 = z - tail
    zr_libm_put(y, 0, y0)
    zr_libm_put(y, 1, (z - y0) - tail)
    k
  end

  # x - n*pi/2 as y[0] + y[1] at `y`, and n (__rem_pio2). The caller
  # handles |x| ~<= pi/4, which needs no reduction.
  #: (f64, ptr) -> word
  def zr_libm_rem_pio2(x, y)
    pio2_1 = Machine.f64(0x3FF921FB54400000)
    pio2_1t = Machine.f64(0x3DD0B4611A626331)
    sign = zr_libm_bits(x) >> 63
    ix = zr_libm_high(x) & 0x7FFFFFFF
    medium = false
    if ix <= 0x400F6A7A
      # |x| ~<= 5pi/4. |x| ~= pi/2 or 2pi/2 cancels: the medium case.
      if (ix & 0xFFFFF) == 0x921FB
        medium = true
      elsif ix <= 0x4002D97C
        # |x| ~<= 3pi/4
        return zr_libm_rem_pio2_near(x, y, 1, sign != 0)
      else
        return zr_libm_rem_pio2_near(x, y, 2, sign != 0)
      end
    elsif ix <= 0x401C463B
      # |x| ~<= 9pi/4
      if ix <= 0x4015FDBC
        # |x| ~<= 7pi/4; |x| ~= 3pi/2 is the medium case.
        if ix == 0x4012D97C
          medium = true
        else
          return zr_libm_rem_pio2_near(x, y, 3, sign != 0)
        end
      elsif ix == 0x401921FB
        # |x| ~= 4pi/2
        medium = true
      else
        return zr_libm_rem_pio2_near(x, y, 4, sign != 0)
      end
    end
    if medium || ix < 0x413921FB
      # |x| ~< 2**20*(pi/2): rint(x/(pi/2)).
      toint = Machine.f64(0x4338000000000000) # 1.5/EPS
      fn = (x * Machine.f64(0x3FE45F306DC9C883)) + toint - toint
      n = Machine.to_int(fn)
      r = x - (fn * pio2_1)
      # The first round, good to 85 bits.
      w = fn * pio2_1t
      # This matters in a directed rounding.
      pio4 = Machine.f64(0x3FE921FB54442D18)
      one = Machine.f64(0x3FF0000000000000)
      if r - w < -pio4
        n -= 1
        fn -= one
        r = x - (fn * pio2_1)
        w = fn * pio2_1t
      elsif r - w > pio4
        n += 1
        fn += one
        r = x - (fn * pio2_1)
        w = fn * pio2_1t
      end
      y0 = r - w
      ey = Machine.word((zr_libm_bits(y0) >> 52) & 0x7FF)
      ex = ix >> 20
      if ex - ey > 16
        # The second round, good to 118 bits.
        t = r
        w = fn * Machine.f64(0x3DD0B4611A600000) # pio2_2
        r = t - w
        w = (fn * Machine.f64(0x3BA3198A2E037073)) - ((t - r) - w) # pio2_2t
        y0 = r - w
        ey = Machine.word((zr_libm_bits(y0) >> 52) & 0x7FF)
        if ex - ey > 49
          # The third round, good to 151 bits: it covers all cases.
          t = r
          w = fn * Machine.f64(0x3BA3198A2E000000) # pio2_3
          r = t - w
          w = (fn * Machine.f64(0x397B839A252049C1)) - ((t - r) - w) # pio2_3t
          y0 = r - w
        end
      end
      zr_libm_put(y, 0, y0)
      zr_libm_put(y, 1, (r - y0) - w)
      return n
    end
    # All other (large) arguments. x is inf or NaN:
    if ix >= 0x7FF00000
      zr_libm_put(y, 0, x - x)
      zr_libm_put(y, 1, x - x)
      return 0
    end
    # z = scalbn(|x|, -ilogb(x) + 23)
    z = Machine.f64((zr_libm_bits(x) & 0x000FFFFFFFFFFFFF) | (Machine.ptr(0x3FF + 23) << 52))
    tx = Machine.slot(24)
    ty = Machine.slot(16)
    i = 0
    while i < 2
      zr_libm_put(tx, i, Machine.to_f64(Machine.to_int(z)))
      z = (z - zr_libm_at(tx, i)) * Machine.f64(0x4170000000000000) # 0x1p24
      i += 1
    end
    zr_libm_put(tx, i, z)
    # Skip the zero terms; the first term is not zero.
    while zr_libm_at(tx, i) == Machine.f64(0)
      i -= 1
    end
    n = zr_libm_rem_pio2_large(tx, ty, (ix >> 20) - (0x3FF + 23), i + 1)
    if sign != 0
      zr_libm_put(y, 0, -zr_libm_at(ty, 0))
      zr_libm_put(y, 1, -zr_libm_at(ty, 1))
      return -n
    end
    zr_libm_put(y, 0, zr_libm_at(ty, 0))
    zr_libm_put(y, 1, zr_libm_at(ty, 1))
    n
  end

  # The 24-bit chunk `i` of the array `iq`, a word each.
  #: (ptr, word) -> word
  def zr_libm_iq(iq, i)
    Machine.load64(iq + (i * 8), 0)
  end

  #: (ptr, word, word) -> void
  def zr_libm_set_iq(iq, i, v)
    Machine.store64(iq + (i * 8), 0, v)
  end

  # The 24 bits `j` of 2/pi, as a double.
  #: (word) -> f64
  def zr_libm_ipio2(j)
    Machine.to_f64(Machine.sword(Machine.load32(zr_libm_ipio2_table() + (j * 4), 0)))
  end

  # x - n*pi/2 for a large x, as y[0] + y[1] at `y`, and n mod 8
  # (__rem_pio2_large with prec 1: 53 bits). `x` has `nx` doubles of 24
  # bits; the exponent of the first is `e0`.
  #: (ptr, ptr, word, word) -> word
  def zr_libm_rem_pio2_large(x, y, e0, nx)
    # @type var i: word
    # @type var j: word
    # @type var k: word
    # @type var fw: f64
    # @type var z: f64
    # @type var n: word
    # @type var ih: word
    # @type var jz: word
    # @type var q0: word
    p24 = Machine.f64(0x4170000000000000) # 0x1p24
    pm24 = Machine.f64(0x3E70000000000000) # 0x1p-24
    zero = Machine.f64(0)
    one = Machine.f64(0x3FF0000000000000)
    iq = Machine.slot(160)
    f = Machine.slot(160)
    fq = Machine.slot(160)
    q = Machine.slot(160)
    jk = 4
    jp = jk
    # jx, jv and q0; q0 < 3.
    jx = nx - 1
    jv = Machine.sdiv(e0 - 3, 24)
    jv = 0 if jv < 0
    q0 = e0 - (24 * (jv + 1))
    # f[0] to f[jx+jk], with f[jx+jk] = ipio2[jv+jk].
    j = jv - jx
    m = jx + jk
    i = 0
    while i <= m
      zr_libm_put(f, i, j < 0 ? zero : zr_libm_ipio2(j))
      i += 1
      j += 1
    end
    # q[0], q[1], ... q[jk]
    i = 0
    while i <= jk
      fw = zero
      j = 0
      while j <= jx
        fw += zr_libm_at(x, j) * zr_libm_at(f, jx + i - j)
        j += 1
      end
      zr_libm_put(q, i, fw)
      i += 1
    end
    jz = jk
    n = 0
    ih = 0
    z = zero
    while true
      # Distill q[] into iq[], in reverse.
      i = 0
      j = jz
      z = zr_libm_at(q, jz)
      while j > 0
        fw = Machine.to_f64(Machine.to_int(pm24 * z))
        zr_libm_set_iq(iq, i, Machine.to_int(z - (p24 * fw)))
        z = zr_libm_at(q, j - 1) + fw
        i += 1
        j -= 1
      end
      # n: the actual value of z, without its integer part >= 8.
      z = ldexp(z, Machine.i32(q0))
      z -= Machine.f64(0x4020000000000000) * Machine.floor(z * Machine.f64(0x3FC0000000000000)) # 8.0, 0.125
      n = Machine.to_int(z)
      z -= Machine.to_f64(n)
      ih = 0
      if q0 > 0
        # n needs iq[jz-1].
        i = zr_libm_iq(iq, jz - 1) >> (24 - q0)
        n += i
        zr_libm_set_iq(iq, jz - 1, zr_libm_iq(iq, jz - 1) - (i << (24 - q0)))
        ih = zr_libm_iq(iq, jz - 1) >> (23 - q0)
      elsif q0 == 0
        ih = zr_libm_iq(iq, jz - 1) >> 23
      elsif z >= Machine.f64(0x3FE0000000000000)
        ih = 2
      end
      if ih > 0
        # q > 0.5: 1 - q.
        n += 1
        carry = 0
        i = 0
        while i < jz
          j = zr_libm_iq(iq, i)
          if carry == 0
            if j != 0
              carry = 1
              zr_libm_set_iq(iq, i, 0x1000000 - j)
            end
          else
            zr_libm_set_iq(iq, i, 0xFFFFFF - j)
          end
          i += 1
        end
        # A rare case: a chance of 1 in 12.
        if q0 == 1
          zr_libm_set_iq(iq, jz - 1, zr_libm_iq(iq, jz - 1) & 0x7FFFFF)
        elsif q0 == 2
          zr_libm_set_iq(iq, jz - 1, zr_libm_iq(iq, jz - 1) & 0x3FFFFF)
        end
        if ih == 2
          z = one - z
          z -= ldexp(one, Machine.i32(q0)) if carry != 0
        end
      end
      # Is a recomputation necessary?
      break if z != zero

      j = 0
      i = jz - 1
      while i >= jk
        j |= zr_libm_iq(iq, i)
        i -= 1
      end
      break if j != 0

      # k: the number of terms necessary.
      k = 1
      k += 1 while zr_libm_iq(iq, jk - k) == 0
      # Add q[jz+1] to q[jz+k].
      i = jz + 1
      while i <= jz + k
        zr_libm_put(f, jx + i, zr_libm_ipio2(jv + i))
        fw = zero
        j = 0
        while j <= jx
          fw += zr_libm_at(x, j) * zr_libm_at(f, jx + i - j)
          j += 1
        end
        zr_libm_put(q, i, fw)
        i += 1
      end
      jz += k
    end
    # Chop off the zero terms.
    if z == zero
      jz -= 1
      q0 -= 24
      while zr_libm_iq(iq, jz) == 0
        jz -= 1
        q0 -= 24
      end
    else
      # Break z into 24 bits, if necessary.
      z = ldexp(z, Machine.i32(-q0))
      if z >= p24
        fw = Machine.to_f64(Machine.to_int(pm24 * z))
        zr_libm_set_iq(iq, jz, Machine.to_int(z - (p24 * fw)))
        jz += 1
        q0 += 24
        zr_libm_set_iq(iq, jz, Machine.to_int(fw))
      else
        zr_libm_set_iq(iq, jz, Machine.to_int(z))
      end
    end
    # The integer chunks as doubles.
    fw = ldexp(one, Machine.i32(q0))
    i = jz
    while i >= 0
      zr_libm_put(q, i, fw * Machine.to_f64(zr_libm_iq(iq, i)))
      fw *= pm24
      i -= 1
    end
    # PIo2[0,...,jp]*q[jz,...,0]
    pio2 = zr_libm_pio2_table()
    i = jz
    while i >= 0
      fw = zero
      k = 0
      while k <= jp && k <= jz - i
        fw += zr_libm_at(pio2, k) * zr_libm_at(q, i + k)
        k += 1
      end
      zr_libm_put(fq, jz - i, fw)
      i -= 1
    end
    # Compress fq[] into y[].
    fw = zero
    i = jz
    while i >= 0
      fw += zr_libm_at(fq, i)
      i -= 1
    end
    zr_libm_put(y, 0, ih == 0 ? fw : -fw)
    fw = zr_libm_at(fq, 0) - fw
    i = 1
    while i <= jz
      fw += zr_libm_at(fq, i)
      i += 1
    end
    zr_libm_put(y, 1, ih == 0 ? fw : -fw)
    n & 7
  end

  # sin(3).
  #: (f64) -> f64
  def sin(x)
    ix = zr_libm_high(x) & 0x7FFFFFFF
    # |x| ~< pi/4
    if ix <= 0x3FE921FB
      # |x| < 2**-26
      return x if ix < 0x3E500000

      return zr_libm_k_sin(x, Machine.f64(0), 0)
    end
    # sin(Inf or NaN) is NaN
    return x - x if ix >= 0x7FF00000

    # Argument reduction.
    y = Machine.slot(16)
    n = zr_libm_rem_pio2(x, y) & 3
    y0 = zr_libm_at(y, 0)
    y1 = zr_libm_at(y, 1)
    return zr_libm_k_sin(y0, y1, 1) if n == 0
    return zr_libm_k_cos(y0, y1) if n == 1
    return -zr_libm_k_sin(y0, y1, 1) if n == 2

    -zr_libm_k_cos(y0, y1)
  end

  # cos(3).
  #: (f64) -> f64
  def cos(x)
    ix = zr_libm_high(x) & 0x7FFFFFFF
    # |x| ~< pi/4
    if ix <= 0x3FE921FB
      # |x| < 2**-27 * sqrt(2)
      return Machine.f64(0x3FF0000000000000) if ix < 0x3E46A09E

      return zr_libm_k_cos(x, Machine.f64(0))
    end
    # cos(Inf or NaN) is NaN
    return x - x if ix >= 0x7FF00000

    # Argument reduction.
    y = Machine.slot(16)
    n = zr_libm_rem_pio2(x, y) & 3
    y0 = zr_libm_at(y, 0)
    y1 = zr_libm_at(y, 1)
    return zr_libm_k_cos(y0, y1) if n == 0
    return -zr_libm_k_sin(y0, y1, 1) if n == 1
    return -zr_libm_k_cos(y0, y1) if n == 2

    zr_libm_k_sin(y0, y1, 1)
  end

  # tan(3).
  #: (f64) -> f64
  def tan(x)
    ix = zr_libm_high(x) & 0x7FFFFFFF
    # |x| ~< pi/4
    if ix <= 0x3FE921FB
      # |x| < 2**-27
      return x if ix < 0x3E400000

      return zr_libm_k_tan(x, Machine.f64(0), 0)
    end
    # tan(Inf or NaN) is NaN
    return x - x if ix >= 0x7FF00000

    # Argument reduction.
    y = Machine.slot(16)
    n = zr_libm_rem_pio2(x, y)
    zr_libm_k_tan(zr_libm_at(y, 0), zr_libm_at(y, 1), n & 1)
  end
end
