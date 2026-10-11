# asin, acos, atan and atan2, ported from musl 1.2.5's asin.c, acos.c,
# atan.c and atan2.c (from FreeBSD; Copyright (C) 1993 by Sun
# Microsystems, Inc.). See THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # The rational approximation R(z) of asin.c and acos.c.
  #: (f64) -> f64
  def zr_libm_asin_r(z)
    p = Machine.f64(0x3F49EFE07501B288) + (z * Machine.f64(0x3F023DE10DFDF709)) # pS4 + z*pS5
    p = Machine.f64(Machine.word(0xBFA48228B5688F3B)) + (z * p) # pS3
    p = Machine.f64(0x3FC9C1550E884455) + (z * p) # pS2
    p = Machine.f64(Machine.word(0xBFD4D61203EB6F7D)) + (z * p) # pS1
    p = z * (Machine.f64(0x3FC5555555555555) + (z * p)) # pS0
    q = Machine.f64(Machine.word(0xBFE6066C1B8D0159)) + (z * Machine.f64(0x3FB3B8C5B12E9282)) # qS3 + z*qS4
    q = Machine.f64(0x40002AE59C598AC8) + (z * q) # qS2
    q = Machine.f64(0x3FF0000000000000) + (z * (Machine.f64(Machine.word(0xC0033A271C8A2D4B)) + (z * q))) # qS1
    p / q
  end

  # asin(3).
  #: (f64) -> f64
  def asin(x)
    pio2_hi = Machine.f64(0x3FF921FB54442D18)
    pio2_lo = Machine.f64(0x3C91A62633145C07)
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    half = Machine.f64(0x3FE0000000000000)
    hx = zr_libm_high(x)
    ix = hx & 0x7FFFFFFF
    # |x| >= 1 or NaN
    if ix >= 0x3FF00000
      # asin(1) = +-pi/2, inexact
      return (x * pio2_hi) + Machine.f64(0x3870000000000000) if ix == 0x3FF00000 && zr_libm_low(x) == 0 # 0x1p-120f

      return Machine.f64(0) / (x - x)
    end
    # |x| < 0.5
    if ix < 0x3FE00000
      # 0x1p-1022 <= |x| < 0x1p-26 does not raise underflow.
      return x if ix < 0x3E500000 && ix >= 0x00100000

      return x + (x * zr_libm_asin_r(x * x))
    end
    # 1 > |x| >= 0.5
    z = (one - Machine.fabs(x)) * half
    s = Machine.sqrt(z)
    r = zr_libm_asin_r(z)
    if ix >= 0x3FEF3333
      # |x| > 0.975
      x = pio2_hi - ((two * (s + (s * r))) - pio2_lo)
    else
      # f+c = sqrt(z)
      f = zr_libm_with_low(s, 0)
      c = (z - (f * f)) / (s + f)
      x = (half * pio2_hi) - ((two * s * r) - (pio2_lo - (two * c)) - ((half * pio2_hi) - (two * f)))
    end
    return -x if (hx >> 31) != 0

    x
  end

  # acos(3).
  #: (f64) -> f64
  def acos(x)
    pio2_hi = Machine.f64(0x3FF921FB54442D18)
    pio2_lo = Machine.f64(0x3C91A62633145C07)
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    half = Machine.f64(0x3FE0000000000000)
    hx = zr_libm_high(x)
    ix = hx & 0x7FFFFFFF
    # |x| >= 1 or NaN
    if ix >= 0x3FF00000
      if ix == 0x3FF00000 && zr_libm_low(x) == 0
        # acos(1) = 0, acos(-1) = pi
        return (two * pio2_hi) + Machine.f64(0x3870000000000000) if (hx >> 31) != 0 # 0x1p-120f

        return Machine.f64(0)
      end
      return Machine.f64(0) / (x - x)
    end
    # |x| < 0.5
    if ix < 0x3FE00000
      # |x| < 2**-57
      return pio2_hi + Machine.f64(0x3870000000000000) if ix <= 0x3C600000

      return pio2_hi - (x - (pio2_lo - (x * zr_libm_asin_r(x * x))))
    end
    # x < -0.5
    if (hx >> 31) != 0
      z = (one + x) * half
      s = Machine.sqrt(z)
      w = (zr_libm_asin_r(z) * s) - pio2_lo
      return two * (pio2_hi - (s + w))
    end
    # x > 0.5
    z = (one - x) * half
    s = Machine.sqrt(z)
    df = zr_libm_with_low(s, 0)
    c = (z - (df * df)) / (s + df)
    w = (zr_libm_asin_r(z) * s) + c
    two * (df + w)
  end

  # atan.c's atanhi: atan(0.5), atan(1.0), atan(1.5) and atan(inf), high
  # parts.
  #: (word) -> f64
  def zr_libm_atanhi(id)
    return Machine.f64(0x3FDDAC670561BB4F) if id == 0
    return Machine.f64(0x3FE921FB54442D18) if id == 1
    return Machine.f64(0x3FEF730BD281F69B) if id == 2

    Machine.f64(0x3FF921FB54442D18)
  end

  # atan.c's atanlo: the low parts.
  #: (word) -> f64
  def zr_libm_atanlo(id)
    return Machine.f64(0x3C7A2B7F222F65E2) if id == 0
    return Machine.f64(0x3C81A62633145C07) if id == 1
    return Machine.f64(0x3C7007887AF0CBBD) if id == 2

    Machine.f64(0x3C91A62633145C07)
  end

  # atan(3).
  #: (f64) -> f64
  def atan(x)
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    onehalf = Machine.f64(0x3FF8000000000000)
    hx = zr_libm_high(x)
    sign = hx >> 31
    ix = hx & 0x7FFFFFFF
    if ix >= 0x44100000
      # |x| >= 2**66
      return x if x != x

      z = zr_libm_atanhi(3) + Machine.f64(0x3870000000000000) # 0x1p-120f
      return sign != 0 ? -z : z
    end
    if ix < 0x3FDC0000
      # |x| < 0.4375; |x| < 2**-27 stays.
      return x if ix < 0x3E400000

      id = -1
    else
      x = Machine.fabs(x)
      if ix < 0x3FF30000
        # |x| < 1.1875
        if ix < 0x3FE60000
          # 7/16 <= |x| < 11/16
          id = 0
          x = ((two * x) - one) / (two + x)
        else
          # 11/16 <= |x| < 19/16
          id = 1
          x = (x - one) / (x + one)
        end
      elsif ix < 0x40038000
        # |x| < 2.4375
        id = 2
        x = (x - onehalf) / (one + (onehalf * x))
      else
        # 2.4375 <= |x| < 2**66
        id = 3
        x = -one / x
      end
    end
    # The end of the argument reduction.
    z = x * x
    w = z * z
    # The sum of aT[i]z**(i+1) for i from 0 to 10, as an odd and an even
    # polynomial.
    s1 = Machine.f64(0x3FA97B4B24760DEB) + (w * Machine.f64(0x3F90AD3AE322DA11)) # aT[8] + w*aT[10]
    s1 = Machine.f64(0x3FB10D66A0D03D51) + (w * s1) # aT[6]
    s1 = Machine.f64(0x3FB745CDC54C206E) + (w * s1) # aT[4]
    s1 = Machine.f64(0x3FC24924920083FF) + (w * s1) # aT[2]
    s1 = z * (Machine.f64(0x3FD555555555550D) + (w * s1)) # aT[0]
    s2 = Machine.f64(Machine.word(0xBFADDE2D52DEFD9A)) + (w * Machine.f64(Machine.word(0xBFA2B4442C6A6C2F))) # aT[7] + w*aT[9]
    s2 = Machine.f64(Machine.word(0xBFB3B0F2AF749A6D)) + (w * s2) # aT[5]
    s2 = Machine.f64(Machine.word(0xBFBC71C6FE231671)) + (w * s2) # aT[3]
    s2 = w * (Machine.f64(Machine.word(0xBFC999999998EBC4)) + (w * s2)) # aT[1]
    return x - (x * (s1 + s2)) if id < 0

    z = zr_libm_atanhi(id) - ((x * (s1 + s2)) - zr_libm_atanlo(id) - x)
    sign != 0 ? -z : z
  end

  # atan2(3).
  #: (f64, f64) -> f64
  def atan2(y, x)
    pi = Machine.f64(0x400921FB54442D18)
    pi_lo = Machine.f64(0x3CA1A62633145C07)
    two = Machine.f64(0x4000000000000000)
    four = Machine.f64(0x4010000000000000)
    return x + y if x != x || y != y

    ix = zr_libm_high(x)
    lx = zr_libm_low(x)
    iy = zr_libm_high(y)
    ly = zr_libm_low(y)
    # x = 1.0
    return atan(y) if ix == 0x3FF00000 && lx == 0

    # 2*sign(x)+sign(y)
    m = ((iy >> 31) & 1) | ((ix >> 30) & 2)
    ix &= 0x7FFFFFFF
    iy &= 0x7FFFFFFF
    # y = 0
    if (iy | ly) == 0
      # atan(+-0,+anything)=+-0, atan(+0,-anything) = pi, atan(-0,-anything) =-pi
      return y if m < 2
      return pi if m == 2

      return -pi
    end
    # x = 0
    if (ix | lx) == 0
      return (m & 1) != 0 ? -pi / two : pi / two
    end
    # x is INF
    if ix == 0x7FF00000
      if iy == 0x7FF00000
        return pi / four if m == 0
        return -pi / four if m == 1
        return Machine.f64(0x4008000000000000) * pi / four if m == 2 # 3*pi/4

        return -Machine.f64(0x4008000000000000) * pi / four
      end
      return Machine.f64(0) if m == 0
      return -Machine.f64(0) if m == 1
      return pi if m == 2

      return -pi
    end
    # |y/x| > 0x1p64
    if ix + (64 << 20) < iy || iy == 0x7FF00000
      return (m & 1) != 0 ? -pi / two : pi / two
    end
    # z = atan(|y/x|), without a spurious underflow. |y/x| < 0x1p-64 and
    # x < 0 give 0.
    z = (m & 2) != 0 && iy + (64 << 20) < ix ? Machine.f64(0) : atan(Machine.fabs(y / x))
    # atan(+,+)
    return z if m == 0
    # atan(-,+)
    return -z if m == 1
    # atan(+,-)
    return pi - (z - pi_lo) if m == 2

    # atan(-,-)
    (z - pi_lo) - pi
  end
end
