# log, log2, log10 and log1p, ported from musl 1.2.5's log.c and log2.c
# (Copyright (c) 2018, Arm Limited, MIT) and log10.c and log1p.c (from
# FreeBSD; Copyright (C) 1993 by Sun Microsystems, Inc.). See
# THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # log(3).
  #: (f64) -> f64
  def log(x)
    one = Machine.f64(0x3FF0000000000000)
    ix = zr_libm_bits(x)
    top = Machine.word(ix >> 48)
    # 1.0 - 0x1p-4 <= x < 1.0 + 0x1.09p-4: near 1.0, a case of its own.
    if ix >= 0x3FEE000000000000 && ix < 0x3FF1090000000000
      # The sign of zero when x == 1, in a downward rounding.
      return Machine.f64(0) if ix == 0x3FF0000000000000

      r = x - one
      r2 = r * r
      r3 = r * r2
      y = r3 * (Machine.f64(0x3FD5555555555577) + (r * Machine.f64(Machine.word(0xBFCFFFFFFFFFFDCB))) +
                (r2 * Machine.f64(0x3FC999999995DD0C)) +
                (r3 * (Machine.f64(Machine.word(0xBFC55555556745A7)) + (r * Machine.f64(0x3FC24924A344DE30)) +
                       (r2 * Machine.f64(Machine.word(0xBFBFFFFFA4423D65))) +
                       (r3 * (Machine.f64(0x3FBC7184282AD6CA) + (r * Machine.f64(Machine.word(0xBFB999EB43B068FF))) +
                              (r2 * Machine.f64(0x3FB78182F7AFD085)) + (r3 * Machine.f64(Machine.word(0xBFB5521375D145CD))))))))
      # The worst error is about 0.507 ULP.
      w = r * Machine.f64(0x41A0000000000000) # 0x1p27
      rhi = r + w - w
      rlo = r - rhi
      b0 = Machine.f64(Machine.word(0xBFE0000000000000)) # B[0] == -0.5
      w = rhi * rhi * b0
      hi = r + w
      lo = r - hi + w
      lo += b0 * rlo * (rhi + r)
      y += lo
      y += hi
      return y
    end
    if top < 0x0010 || top >= 0x7FF0
      # x < 0x1p-1022, an infinity or NaN.
      return zr_libm_divzero(1) if (ix & 0x7FFFFFFFFFFFFFFF) == 0
      # log(inf) == inf
      return x if ix == 0x7FF0000000000000
      return zr_libm_invalid(x) if (top & 0x8000) != 0 || (top & 0x7FF0) == 0x7FF0

      # A subnormal x: normalize it.
      ix = zr_libm_bits(x * Machine.f64(0x4330000000000000)) # 0x1p52
      ix -= Machine.ptr(52) << 52
    end
    # x = 2**k z, with z in [OFF, 2*OFF) and exact. The range has N = 128
    # parts; the ith contains z and has c near its center.
    tmp = Machine.sub_wrap(Machine.word(ix), 0x3FE6000000000000)
    i = (tmp >> 45) & 127
    k = tmp >> 52
    iz = Machine.ptr(Machine.usub_wrap(ix, Machine.ptr(tmp) & 0xFFF0000000000000))
    t = zr_libm_log_table() + (i * 32)
    invc = Machine.f64(Machine.load64(t, 0))
    logc = Machine.f64(Machine.load64(t, 8))
    z = Machine.f64(iz)
    # log(x) = log1p(z/c-1) + log(c) + k*Ln2, with r ~= z/c - 1 and
    # |r| < 1/(2*N).
    r = (z - Machine.f64(Machine.load64(t, 16)) - Machine.f64(Machine.load64(t, 24))) * invc
    kd = Machine.to_f64(k)
    # hi + lo = r + log(c) + k*Ln2.
    w = (kd * Machine.f64(0x3FE62E42FEFA3800)) + logc
    hi = w + r
    lo = w - hi + r + (kd * Machine.f64(0x3D2EF35793C76730))
    # log(x) = lo + (log1p(r) - r) + hi.
    r2 = r * r
    lo + (r2 * Machine.f64(Machine.word(0xBFE0000000000001))) +
      (r * r2 * (Machine.f64(0x3FD555555551305B) + (r * Machine.f64(Machine.word(0xBFCFFFFFFFEB4590))) +
                 (r2 * (Machine.f64(0x3FC999B324F10111) + (r * Machine.f64(Machine.word(0xBFC55575E506C89F))))))) + hi
  end

  # log2(3).
  #: (f64) -> f64
  def log2(x)
    one = Machine.f64(0x3FF0000000000000)
    invln2hi = Machine.f64(0x3FF7154765200000)
    invln2lo = Machine.f64(0x3DE705FC2EEFA200)
    ix = zr_libm_bits(x)
    top = Machine.word(ix >> 48)
    # 1.0 - 0x1.5b51p-5 <= x < 1.0 + 0x1.6ab2p-5: near 1.0, a case of its
    # own.
    if ix >= 0x3FEEA4AF00000000 && ix < 0x3FF0B55900000000
      # The sign of zero when x == 1, in a downward rounding.
      return Machine.f64(0) if ix == 0x3FF0000000000000

      r = x - one
      rhi = Machine.f64(zr_libm_bits(r) & 0xFFFFFFFF00000000)
      rlo = r - rhi
      hi = rhi * invln2hi
      lo = (rlo * invln2hi) + (r * invln2lo)
      r2 = r * r
      r4 = r2 * r2
      # The worst error is below 0.55 ULP.
      p = r2 * (Machine.f64(Machine.word(0xBFE71547652B82FE)) + (r * Machine.f64(0x3FDEC709DC3A03F7)))
      y = hi + p
      lo += hi - y + p
      lo += r4 * (Machine.f64(Machine.word(0xBFD71547652B7C3F)) + (r * Machine.f64(0x3FD2776C50F05BE4)) +
                  (r2 * (Machine.f64(Machine.word(0xBFCEC709DD768FE5)) + (r * Machine.f64(0x3FCA61761EC4E736)))) +
                  (r4 * (Machine.f64(Machine.word(0xBFC7153FBC64A79B)) + (r * Machine.f64(0x3FC484D154F01B4A)) +
                         (r2 * (Machine.f64(Machine.word(0xBFC289E4A72C383C)) + (r * Machine.f64(0x3FC0B32F285AEE66)))))))
      y += lo
      return y
    end
    if top < 0x0010 || top >= 0x7FF0
      # x < 0x1p-1022, an infinity or NaN.
      return zr_libm_divzero(1) if (ix & 0x7FFFFFFFFFFFFFFF) == 0
      # log(inf) == inf
      return x if ix == 0x7FF0000000000000
      return zr_libm_invalid(x) if (top & 0x8000) != 0 || (top & 0x7FF0) == 0x7FF0

      # A subnormal x: normalize it.
      ix = zr_libm_bits(x * Machine.f64(0x4330000000000000)) # 0x1p52
      ix -= Machine.ptr(52) << 52
    end
    # x = 2**k z, with z in [OFF, 2*OFF) and exact. The range has N = 64
    # parts; the ith contains z and has c near its center.
    tmp = Machine.sub_wrap(Machine.word(ix), 0x3FE6000000000000)
    i = (tmp >> 46) & 63
    k = tmp >> 52
    iz = Machine.ptr(Machine.usub_wrap(ix, Machine.ptr(tmp) & 0xFFF0000000000000))
    t = zr_libm_log2_table() + (i * 32)
    invc = Machine.f64(Machine.load64(t, 0))
    logc = Machine.f64(Machine.load64(t, 8))
    z = Machine.f64(iz)
    kd = Machine.to_f64(k)
    # log2(x) = log2(z/c) + log2(c) + k, with r ~= z/c - 1 and |r| <
    # 1/(2*N).
    r = (z - Machine.f64(Machine.load64(t, 16)) - Machine.f64(Machine.load64(t, 24))) * invc
    rhi = Machine.f64(zr_libm_bits(r) & 0xFFFFFFFF00000000)
    rlo = r - rhi
    t1 = rhi * invln2hi
    t2 = (rlo * invln2hi) + (r * invln2lo)
    # hi + lo = r/ln2 + log2(c) + k.
    t3 = kd + logc
    hi = t3 + t1
    lo = t3 - hi + t1 + t2
    # log2(r+1) = r/ln2 + r**2*poly(r).
    r2 = r * r
    r4 = r2 * r2
    p = Machine.f64(Machine.word(0xBFE71547652B8339)) + (r * Machine.f64(0x3FDEC709DC3A04BE)) +
        (r2 * (Machine.f64(Machine.word(0xBFD7154764702FFB)) + (r * Machine.f64(0x3FD2776C50034C48)))) +
        (r4 * (Machine.f64(Machine.word(0xBFCEC7B328EA92BC)) + (r * Machine.f64(0x3FCA6225E117F92E))))
    lo + (r2 * p) + hi
  end

  # log(1+f) - f for f in [sqrt(2)/2 - 1, sqrt(2) - 1], less hfsq: the
  # polynomial R of log10.c and log1p.c, as s*(hfsq+R).
  #: (f64, f64) -> f64
  def zr_libm_log_poly(f, hfsq)
    s = f / (Machine.f64(0x4000000000000000) + f)
    z = s * s
    w = z * z
    t1 = w * (Machine.f64(0x3FD999999997FA04) + (w * (Machine.f64(0x3FCC71C51D8E78AF) + (w * Machine.f64(0x3FC39A09D078C69F)))))
    t2 = z * (Machine.f64(0x3FE5555555555593) + (w * (Machine.f64(0x3FD2492494229359) +
                                                     (w * (Machine.f64(0x3FC7466496CB03DE) + (w * Machine.f64(0x3FC2F112DF3E5244)))))))
    s * (hfsq + (t2 + t1))
  end

  # log10(3).
  #: (f64) -> f64
  def log10(x)
    hx = zr_libm_high(x)
    k = 0
    if hx < 0x00100000 || (hx >> 31) != 0
      # log(+-0) = -inf
      return -Machine.f64(0x3FF0000000000000) / (x * x) if (zr_libm_bits(x) & 0x7FFFFFFFFFFFFFFF) == 0
      # log(-#) = NaN
      return (x - x) / Machine.f64(0) if (hx >> 31) != 0

      # A subnormal number: scale x up.
      k -= 54
      x *= Machine.f64(0x4350000000000000) # 0x1p54
      hx = zr_libm_high(x)
    elsif hx >= 0x7FF00000
      return x
    elsif hx == 0x3FF00000 && zr_libm_low(x) == 0
      return Machine.f64(0)
    end
    # Reduce x into [sqrt(2)/2, sqrt(2)].
    hx += 0x3FF00000 - 0x3FE6A09E
    k += (hx >> 20) - 0x3FF
    hx = (hx & 0x000FFFFF) + 0x3FE6A09E
    x = zr_libm_with_high(x, hx)
    f = x - Machine.f64(0x3FF0000000000000)
    hfsq = Machine.f64(0x3FE0000000000000) * f * f
    # hi+lo = f - hfsq + s*(hfsq+R) ~ log(1+f)
    hi = Machine.f64(zr_libm_bits(f - hfsq) & 0xFFFFFFFF00000000)
    lo = f - hi - hfsq + zr_libm_log_poly(f, hfsq)
    # val_hi+val_lo ~ log10(1+f) + k*log10(2)
    val_hi = hi * Machine.f64(0x3FDBCB7B15200000)
    dk = Machine.to_f64(k)
    y = dk * Machine.f64(0x3FD34413509F6000)
    val_lo = (dk * Machine.f64(0x3D59FEF311F12B36)) + ((lo + hi) * Machine.f64(0x3DBB9438CA9AADD5)) +
             (lo * Machine.f64(0x3FDBCB7B15200000))
    # More precision to add y: it costs little, and it makes the error
    # smaller for many arguments.
    w = y + val_hi
    val_lo += (y - w) + val_hi
    val_hi = w
    val_lo + val_hi
  end

  # log1p(3).
  #: (f64) -> f64
  def log1p(x)
    one = Machine.f64(0x3FF0000000000000)
    hx = zr_libm_high(x)
    k = 1
    c = Machine.f64(0)
    f = Machine.f64(0)
    if hx < 0x3FDA827A || (hx >> 31) != 0
      # 1+x < sqrt(2)+
      if hx >= 0xBFF00000
        # x <= -1.0: log1p(-1) = -inf, and log1p(x < -1) = NaN.
        return x / Machine.f64(0) if x == -one

        return (x - x) / Machine.f64(0)
      end
      # |x| < 2**-53
      return x if (hx & 0x7FFFFFFF) < 0x3CA00000

      if hx <= 0xBFD2BEC4
        # sqrt(2)/2- <= 1+x < sqrt(2)+
        k = 0
        f = x
      end
    elsif hx >= 0x7FF00000
      return x
    end
    if k != 0
      u = one + x
      hu = zr_libm_high(u)
      hu += 0x3FF00000 - 0x3FE6A09E
      k = (hu >> 20) - 0x3FF
      # A correction term ~ log(1+x)-log(u), without underflow in c/u.
      if k < 54
        c = k >= 2 ? one - (u - x) : x - (u - one)
        c /= u
      end
      # Reduce u into [sqrt(2)/2, sqrt(2)].
      hu = (hu & 0x000FFFFF) + 0x3FE6A09E
      u = zr_libm_with_high(u, hu)
      f = u - one
    end
    hfsq = Machine.f64(0x3FE0000000000000) * f * f
    dk = Machine.to_f64(k)
    zr_libm_log_poly(f, hfsq) + ((dk * Machine.f64(0x3DEA39EF35793C76)) + c) - hfsq + f + (dk * Machine.f64(0x3FE62E42FEE00000))
  end
end
