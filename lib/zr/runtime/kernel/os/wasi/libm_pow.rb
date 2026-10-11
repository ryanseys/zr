# fmod, hypot and pow, ported from musl 1.2.5's fmod.c and hypot.c (musl,
# MIT) and pow.c (Copyright (c) 2018, Arm Limited, MIT). See
# THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # fmod(3): x - n*y for the integer n that truncates x/y, exact.
  #: (f64, f64) -> f64
  def fmod(x, y)
    # @type var ex: word
    # @type var ey: word
    # @type var i: ptr
    # @type var uxi: ptr
    uxi = zr_libm_bits(x)
    uyi = zr_libm_bits(y)
    ex = Machine.word((uxi >> 52) & 0x7FF)
    ey = Machine.word((uyi >> 52) & 0x7FF)
    sx = uxi >> 63
    if (uyi & 0x7FFFFFFFFFFFFFFF) == 0 || y != y || ex == 0x7FF
      return (x * y) / (x * y)
    end
    if (uxi & 0x7FFFFFFFFFFFFFFF) <= (uyi & 0x7FFFFFFFFFFFFFFF)
      return Machine.f64(0) * x if (uxi & 0x7FFFFFFFFFFFFFFF) == (uyi & 0x7FFFFFFFFFFFFFFF)

      return x
    end
    # Normalize x and y.
    if ex == 0
      i = Machine.ushl_wrap(uxi, 12)
      while (i >> 63) == 0
        ex -= 1
        i = Machine.ushl_wrap(i, 1)
      end
      uxi = Machine.ushl_wrap(uxi, Machine.ptr(1 - ex))
    else
      uxi &= 0x000FFFFFFFFFFFFF
      uxi |= Machine.ptr(1) << 52
    end
    if ey == 0
      i = Machine.ushl_wrap(uyi, 12)
      while (i >> 63) == 0
        ey -= 1
        i = Machine.ushl_wrap(i, 1)
      end
      uyi = Machine.ushl_wrap(uyi, Machine.ptr(1 - ey))
    else
      uyi &= 0x000FFFFFFFFFFFFF
      uyi |= Machine.ptr(1) << 52
    end
    # x mod y
    while ex > ey
      i = Machine.ptr(Machine.usub_wrap(uxi, uyi))
      if (i >> 63) == 0
        return Machine.f64(0) * x if i == 0

        uxi = i
      end
      uxi <<= 1
      ex -= 1
    end
    i = Machine.ptr(Machine.usub_wrap(uxi, uyi))
    if (i >> 63) == 0
      return Machine.f64(0) * x if i == 0

      uxi = i
    end
    while (uxi >> 52) == 0
      uxi <<= 1
      ex -= 1
    end
    # Scale the result.
    if ex > 0
      uxi -= Machine.ptr(1) << 52
      uxi |= Machine.ptr(ex) << 52
    else
      uxi >>= Machine.ptr(1 - ex)
    end
    Machine.f64(uxi | (sx << 63))
  end

  # x*x as hi + lo, exact (hypot.c's sq): the low part.
  #: (f64, f64) -> f64
  def zr_libm_sq_lo(x, hi)
    xc = x * Machine.f64(0x41A0000002000000) # 0x1p27 + 1
    xh = x - xc + xc
    xl = x - xh
    (xh * xh) - hi + (Machine.f64(0x4000000000000000) * xh * xl) + (xl * xl)
  end

  # hypot(3).
  #: (f64, f64) -> f64
  def hypot(x, y)
    ux = zr_libm_bits(x) & 0x7FFFFFFFFFFFFFFF
    uy = zr_libm_bits(y) & 0x7FFFFFFFFFFFFFFF
    # |x| >= |y|
    if ux < uy
      ut = ux
      ux = uy
      uy = ut
    end
    ex = Machine.word(ux >> 52)
    ey = Machine.word(uy >> 52)
    x = Machine.f64(ux)
    y = Machine.f64(uy)
    # hypot(inf, nan) == inf
    return y if ey == 0x7FF
    return x if ex == 0x7FF || uy == 0
    # hypot(x, y) ~= x + y*y/x/2, inexact for a small y/x.
    return x + y if ex - ey > 64

    # A precise argument of sqrt, without overflow: xh*xh must not
    # overflow and xl*xl must not underflow in sq.
    z = Machine.f64(0x3FF0000000000000)
    if ex > 0x3FF + 510
      z = Machine.f64(0x6BB0000000000000) # 0x1p700
      x *= Machine.f64(0x1430000000000000) # 0x1p-700
      y *= Machine.f64(0x1430000000000000)
    elsif ey < 0x3FF - 450
      z = Machine.f64(0x1430000000000000)
      x *= Machine.f64(0x6BB0000000000000)
      y *= Machine.f64(0x6BB0000000000000)
    end
    hx = x * x
    lx = zr_libm_sq_lo(x, hx)
    hy = y * y
    ly = zr_libm_sq_lo(y, hy)
    z * Machine.sqrt(ly + lx + hy + hx)
  end

  # pow.c's SIGN_BIAS: 0x800 << EXP_TABLE_BITS.
  LIBM_SIGN_BIAS = 0x40000

  # 0 when the bits `iy` of a finite number that is not zero are not of
  # an integer, 1 for an odd integer, 2 for an even one (checkint).
  #: (ptr) -> word
  def zr_libm_checkint(iy)
    e = Machine.word((iy >> 52) & 0x7FF)
    return 0 if e < 0x3FF
    return 2 if e > 0x3FF + 52
    return 0 if (iy & ((Machine.ptr(1) << (0x3FF + 52 - e)) - 1)) != 0
    return 1 if (iy & (Machine.ptr(1) << (0x3FF + 52 - e))) != 0

    2
  end

  # Whether the bits `i` are of 0, an infinity or NaN (zeroinfnan).
  #: (ptr) -> bool
  def zr_libm_zeroinfnan(i)
    a = i & 0x7FFFFFFFFFFFFFFF
    a == 0 || a >= 0x7FF0000000000000
  end

  # log(x) as the result plus a tail at `tailp` with about 15 more bits
  # (pow.c's log_inline). `ix` has the bits of x, with a subnormal x
  # normalized by the sign bit of the exponent.
  #: (ptr, ptr) -> f64
  def zr_libm_pow_log(ix, tailp)
    # x = 2**k z, with z in [OFF, 2*OFF) and exact. The range has N = 128
    # parts; the ith contains z and has c near its center.
    tmp = Machine.sub_wrap(Machine.word(ix), 0x3FE6955500000000)
    i = (tmp >> 45) & 127
    k = tmp >> 52
    iz = Machine.ptr(Machine.usub_wrap(ix, Machine.ptr(tmp) & 0xFFF0000000000000))
    z = Machine.f64(iz)
    kd = Machine.to_f64(k)
    # log(x) = k*Ln2 + log(c) + log1p(z/c-1).
    t = zr_libm_pow_log_table() + (i * 24)
    invc = Machine.f64(Machine.load64(t, 0))
    logc = Machine.f64(Machine.load64(t, 8))
    logctail = Machine.f64(Machine.load64(t, 16))
    # 1/c is j/N or j/N/2 for an integer j in [N, 2N), and |z/c - 1| <
    # 1/N, so r = z/c - 1 is exact. Split z so that rhi, rlo and rhi*rhi
    # are exact, and |rlo| <= |r|.
    zhi = Machine.f64(Machine.uadd_wrap(iz, Machine.ptr(1) << 31) & 0xFFFFFFFF00000000)
    zlo = z - zhi
    rhi = (zhi * invc) - Machine.f64(0x3FF0000000000000)
    rlo = zlo * invc
    r = rhi + rlo
    # k*Ln2 + log(c) + r.
    t1 = (kd * Machine.f64(0x3FE62E42FEFA3800)) + logc
    t2 = t1 + r
    lo1 = (kd * Machine.f64(0x3D2EF35793C76730)) + logctail
    lo2 = t1 - t2 + r
    # k*Ln2 + log(c) + r + A[0]*r*r, with A[0] = -0.5.
    a0 = Machine.f64(Machine.word(0xBFE0000000000000))
    ar = a0 * r
    ar2 = r * ar
    ar3 = r * ar2
    arhi = a0 * rhi
    arhi2 = rhi * arhi
    hi = t2 + arhi2
    lo3 = rlo * (ar + arhi)
    lo4 = t2 - hi + arhi2
    # p = log1p(r) - r - A[0]*r*r.
    p = ar3 * (Machine.f64(Machine.word(0xBFE5555555555560)) + (r * Machine.f64(0x3FE0000000000006)) +
               (ar2 * (Machine.f64(0x3FE999999959554E) + (r * Machine.f64(Machine.word(0xBFE555555529A47A))) +
                       (ar2 * (Machine.f64(Machine.word(0xBFF2495B9B4845E9)) + (r * Machine.f64(0x3FF0002B8B263FC3)))))))
    lo = lo1 + lo2 + lo3 + lo4 + p
    y = hi + lo
    Machine.store64(tailp, 0, Machine.bits(hi - y + lo))
    y
  end

  # pow(3).
  #: (f64, f64) -> f64
  def pow(x, y)
    sign_bias = 0
    ix = zr_libm_bits(x)
    iy = zr_libm_bits(y)
    topx = Machine.word(ix >> 52)
    topy = Machine.word(iy >> 52)
    # x < 0x1p-126, an infinity or NaN; or |y| < 0x1p-65, |y| >= 0x1p63
    # or NaN.
    if topx == 0 || topx >= 0x7FF || (topy & 0x7FF) < 0x3BE || (topy & 0x7FF) >= 0x43E
      one = Machine.f64(0x3FF0000000000000)
      if zr_libm_zeroinfnan(iy)
        return one if (iy & 0x7FFFFFFFFFFFFFFF) == 0
        return one if ix == 0x3FF0000000000000
        return x + y if (ix & 0x7FFFFFFFFFFFFFFF) > 0x7FF0000000000000 || (iy & 0x7FFFFFFFFFFFFFFF) > 0x7FF0000000000000
        return one if (ix & 0x7FFFFFFFFFFFFFFF) == 0x3FF0000000000000
        # |x| < 1 and y == inf, or |x| > 1 and y == -inf.
        return Machine.f64(0) if ((ix & 0x7FFFFFFFFFFFFFFF) < 0x3FF0000000000000) == ((iy >> 63) == 0)

        return y * y
      end
      if zr_libm_zeroinfnan(ix)
        x2 = x * x
        x2 = -x2 if (ix >> 63) != 0 && zr_libm_checkint(iy) == 1
        return (iy >> 63) != 0 ? one / x2 : x2
      end
      # x and y are finite and not zero.
      if (ix >> 63) != 0
        # Finite x < 0.
        yint = zr_libm_checkint(iy)
        return zr_libm_invalid(x) if yint == 0

        sign_bias = LIBM_SIGN_BIAS if yint == 1
        ix &= 0x7FFFFFFFFFFFFFFF
        topx &= 0x7FF
      end
      if (topy & 0x7FF) < 0x3BE || (topy & 0x7FF) >= 0x43E
        # sign_bias is 0 here, because y is not odd.
        return one if ix == 0x3FF0000000000000
        # |y| < 2**-65: x**y ~= 1 + y*log(x).
        return ix > 0x3FF0000000000000 ? one + y : one - y if (topy & 0x7FF) < 0x3BE
        return zr_libm_oflow(0) if (ix > 0x3FF0000000000000) == (topy < 0x800)

        return zr_libm_uflow(0)
      end
      if topx == 0
        # A subnormal x: normalize it so that its exponent is negative.
        ix = zr_libm_bits(x * Machine.f64(0x4330000000000000)) & 0x7FFFFFFFFFFFFFFF # 0x1p52
        ix -= Machine.ptr(52) << 52
      end
    end
    tailp = Machine.slot(8)
    hi = zr_libm_pow_log(ix, tailp)
    lo = Machine.f64(Machine.load64(tailp, 0))
    yhi = Machine.f64(iy & 0xFFFFFFFFF8000000)
    ylo = y - yhi
    lhi = Machine.f64(zr_libm_bits(hi) & 0xFFFFFFFFF8000000)
    llo = hi - lhi + lo
    ehi = yhi * lhi
    # |elo| < |ehi| * 2**-25
    elo = (ylo * lhi) + (y * llo)
    zr_libm_exp_inline(ehi, elo, sign_bias)
  end
end
