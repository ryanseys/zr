# tgamma and lgamma_r, ported from musl 1.2.5's tgamma.c (musl, MIT; a
# Lanczos approximation, with ideas and constants from boost and python)
# and lgamma_r.c (from FreeBSD; Copyright (C) 1993 by Sun Microsystems,
# Inc.). See THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # sin(pi x) for x > 0x1p-100; when sin(pi*x) == 0, the sign is
  # arbitrary (tgamma.c's sinpi and lgamma_r.c's sin_pi, which do the same
  # operations).
  #: (f64) -> f64
  def zr_libm_sinpi(x)
    half = Machine.f64(0x3FE0000000000000)
    zero = Machine.f64(0)
    # The argument reduction: x = |x| mod 2.
    x *= half
    x = Machine.f64(0x4000000000000000) * (x - Machine.floor(x))
    # Reduce x into [-.25,.25].
    n = Machine.to_int(Machine.f64(0x4010000000000000) * x)
    n = (n + 1) / 2
    x -= Machine.to_f64(n) * half
    x *= Machine.f64(0x400921FB54442D18) # pi
    return zr_libm_k_cos(x, zero) if n == 1
    return zr_libm_k_sin(-x, zero, 0) if n == 2
    return -zr_libm_k_cos(x, zero) if n == 3

    zr_libm_k_sin(x, zero, 0)
  end

  # The rational function S of tgamma.c, for a positive x.
  #: (f64) -> f64
  def zr_libm_gamma_s(x)
    t = zr_libm_gamma_table()
    num = Machine.f64(0)
    den = Machine.f64(0)
    # A large x goes the other way, so that it does not overflow.
    if x < Machine.f64(0x4020000000000000) # 8
      i = 12
      while i >= 0
        num = (num * x) + zr_libm_at(t, 2 * i)
        den = (den * x) + zr_libm_at(t, (2 * i) + 1)
        i -= 1
      end
    else
      i = 0
      while i <= 12
        num = (num / x) + zr_libm_at(t, 2 * i)
        den = (den / x) + zr_libm_at(t, (2 * i) + 1)
        i += 1
      end
    end
    num / den
  end

  # tgamma(3): the Lanczos approximation
  # Gamma(x) = (x + g - 0.5)**(x - 0.5) * S(x) / exp(x + g - 0.5), and for
  # x < 0 the reflection Gamma(x)*Gamma(-x) = -pi/(x sin(pi x)).
  #: (f64) -> f64
  def tgamma(x)
    one = Machine.f64(0x3FF0000000000000)
    half = Machine.f64(0x3FE0000000000000)
    gmhalf = Machine.f64(0x40161945B9800000) # g - 0.5 = 5.524680040776729583740234375
    ix = zr_libm_high(x) & 0x7FFFFFFF
    sign = zr_libm_bits(x) >> 63
    # tgamma(nan)=nan, tgamma(inf)=inf, tgamma(-inf)=nan
    return x + Machine.f64(0x7FF0000000000000) if ix >= 0x7FF00000
    # |x| < 2**-54: tgamma(x) ~ 1/x
    return one / x if ix < (0x3FF - 54) << 20

    # Integer arguments.
    if x == Machine.floor(x)
      return Machine.f64(0) / Machine.f64(0) if sign != 0
      return zr_libm_at(zr_libm_fact_table(), Machine.to_int(x) - 1) if x <= Machine.f64(0x4037000000000000) # 23
    end
    # x >= 172: tgamma(x)=inf with overflow; x =< -184: tgamma(x)=+-0.
    if ix >= 0x40670000
      # |x| >= 184
      if sign != 0
        return Machine.f64(0) if Machine.floor(x) * half == Machine.floor(x * half)

        return -Machine.f64(0)
      end
      return x * Machine.f64(0x7FE0000000000000) # 0x1p1023
    end
    absx = sign != 0 ? -x : x
    # The error of x + g - 0.5.
    y = absx + gmhalf
    if absx > gmhalf
      dy = y - absx
      dy -= gmhalf
    else
      dy = y - gmhalf
      dy -= absx
    end
    z = absx - half
    r = zr_libm_gamma_s(absx) * exp(-y)
    if x < Machine.f64(0)
      # The reflection formula for a negative x. sinpi(absx) is not 0,
      # because the integers are already handled.
      r = -Machine.f64(0x400921FB54442D18) / (zr_libm_sinpi(absx) * absx * r)
      dy = -dy
      z = -z
    end
    r += dy * Machine.f64(0x40181945B9800000) * r / y # gmhalf+0.5
    z = pow(y, half * z)
    r * z * z
  end

  # lgamma_r(3): log|Gamma(x)|, with the sign of Gamma(x) at `signgamp` as
  # an I32.
  #: (f64, ptr) -> f64
  def lgamma_r(x, signgamp)
    # @type var r: f64
    # @type var y: f64
    # @type var i: word
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    half = Machine.f64(0x3FE0000000000000)
    zero = Machine.f64(0)
    tc = Machine.f64(0x3FF762D86356BE3F)
    # Purge off +-inf, NaN, +-0, tiny and negative arguments.
    Machine.store32(signgamp, 0, Machine.i32(1))
    sign = zr_libm_bits(x) >> 63
    ix = zr_libm_high(x) & 0x7FFFFFFF
    return x * x if ix >= 0x7FF00000

    if ix < (0x3FF - 70) << 20
      # |x| < 2**-70: return -log(|x|).
      if sign != 0
        x = -x
        Machine.store32(signgamp, 0, Machine.i32(-1))
      end
      return -log(x)
    end
    nadj = zero
    if sign != 0
      x = -x
      t = zr_libm_sinpi(x)
      # -integer
      return one / (x - x) if t == zero

      if t > zero
        Machine.store32(signgamp, 0, Machine.i32(-1))
      else
        t = -t
      end
      nadj = log(Machine.f64(0x400921FB54442D18) / (t * x)) # pi
    end
    if (ix == 0x3FF00000 || ix == 0x40000000) && zr_libm_low(x) == 0
      # Purge off 1 and 2.
      r = zero
    elsif ix < 0x40000000
      # x < 2.0
      if ix <= 0x3FECCCCC
        # lgamma(x) = lgamma(x+1)-log(x)
        r = -log(x)
        if ix >= 0x3FE76944
          y = one - x
          i = 0
        elsif ix >= 0x3FCDA661
          y = x - (tc - one)
          i = 1
        else
          y = x
          i = 2
        end
      else
        r = zero
        if ix >= 0x3FFBB4C3
          # [1.7316,2]
          y = two - x
          i = 0
        elsif ix >= 0x3FF3B4C4
          # [1.23,1.73]
          y = x - tc
          i = 1
        else
          y = x - one
          i = 2
        end
      end
      r += zr_libm_lgamma_small(y, i)
    elsif ix < 0x40200000
      # x < 8.0
      i = Machine.to_int(x)
      y = x - Machine.to_f64(i)
      p = Machine.f64(0x3F5E26B67368F239) + (y * Machine.f64(0x3F00BFECDD17E945)) # s5 + y*s6
      p = Machine.f64(0x3F9B481C7E939961) + (y * p) # s4
      p = Machine.f64(0x3FC2BB9CBEE5F2F7) + (y * p) # s3
      p = Machine.f64(0x3FD4D98F4F139F59) + (y * p) # s2
      p = Machine.f64(0x3FCB848B36E20878) + (y * p) # s1
      p = y * (Machine.f64(Machine.word(0xBFB3C467E37DB0C8)) + (y * p)) # s0
      q = Machine.f64(0x3F497DDACA41A95B) + (y * Machine.f64(0x3EDEBAF7A5B38140)) # r5 + y*r6
      q = Machine.f64(0x3F9317EA742ED475) + (y * q) # r4
      q = Machine.f64(0x3FC601EDCCFBDF27) + (y * q) # r3
      q = Machine.f64(0x3FE71A1893D3DCDC) + (y * q) # r2
      q = Machine.f64(0x3FF645A762C4AB74) + (y * q) # r1
      q = one + (y * q)
      r = (half * y) + (p / q)
      # lgamma(1+s) = log(s) + lgamma(s)
      z = one
      z *= y + Machine.f64(0x4018000000000000) if i >= 7 # 6.0
      z *= y + Machine.f64(0x4014000000000000) if i >= 6 # 5.0
      z *= y + Machine.f64(0x4010000000000000) if i >= 5 # 4.0
      z *= y + Machine.f64(0x4008000000000000) if i >= 4 # 3.0
      if i >= 3
        z *= y + two
        r += log(z)
      end
    elsif ix < 0x43900000
      # 8.0 <= x < 2**58
      t = log(x)
      z = one / x
      y = z * z
      w = Machine.f64(0x3F4B67BA4CDAD5D1) + (y * Machine.f64(Machine.word(0xBF5AB89D0B9E43E4))) # w5 + y*w6
      w = Machine.f64(Machine.word(0xBF4380CB8C0FE741)) + (y * w) # w4
      w = Machine.f64(0x3F4A019F98CF38B6) + (y * w) # w3
      w = Machine.f64(Machine.word(0xBF66C16C16B02E5C)) + (y * w) # w2
      w = Machine.f64(0x3FDACFE390C97D69) + (z * (Machine.f64(0x3FB555555555553B) + (y * w))) # w0, w1
      r = ((x - half) * (t - one)) + w
    else
      # 2**58 <= x <= inf
      r = x * (log(x) - one)
    end
    r = nadj - r if sign != 0
    r
  end

  # The part of lgamma_r for x < 2 after its reduction to y; `i` picks the
  # approximation.
  #: (f64, word) -> f64
  def zr_libm_lgamma_small(y, i)
    half = Machine.f64(0x3FE0000000000000)
    if i == 0
      z = y * y
      p1 = Machine.f64(0x3F2CF2ECED10E54D) + (z * Machine.f64(0x3EFA7074428CFA52)) # a8 + z*a10
      p1 = Machine.f64(0x3F538A94116F3F5D) + (z * p1) # a6
      p1 = Machine.f64(0x3F7E404FB68FEFE8) + (z * p1) # a4
      p1 = Machine.f64(0x3FB13E001A5562A7) + (z * p1) # a2
      p1 = Machine.f64(0x3FB3C467E37DB0C8) + (z * p1) # a0
      p2 = Machine.f64(0x3F1C5088987DFB07) + (z * Machine.f64(0x3F07858E90A45837)) # a9 + z*a11
      p2 = Machine.f64(0x3F40B6C689B99C00) + (z * p2) # a7
      p2 = Machine.f64(0x3F67ADD8CCB7926B) + (z * p2) # a5
      p2 = Machine.f64(0x3F951322AC92547B) + (z * p2) # a3
      p2 = z * (Machine.f64(0x3FD4A34CC4A60FAD) + (z * p2)) # a1
      p = (y * p1) + p2
      return p - (half * y)
    end
    if i == 1
      z = y * y
      w = z * y
      p1 = Machine.f64(Machine.word(0xBF56FE8EBF2D1AF1)) + (w * Machine.f64(0x3F34AF6D6C0EBBF7)) # t9 + w*t12
      p1 = Machine.f64(0x3F78FCE0E370E344) + (w * p1) # t6
      p1 = Machine.f64(Machine.word(0xBFA0C9A8DF35B713)) + (w * p1) # t3
      p1 = Machine.f64(0x3FDEF72BC8EE38A2) + (w * p1) # t0
      p2 = Machine.f64(0x3F4CDF0CEF61A8E9) + (w * Machine.f64(Machine.word(0xBF347F24ECC38C38))) # t10 + w*t13
      p2 = Machine.f64(Machine.word(0xBF6E2EFFB3E914D7)) + (w * p2) # t7
      p2 = Machine.f64(0x3F9266E7970AF9EC) + (w * p2) # t4
      p2 = Machine.f64(Machine.word(0xBFC2E4278DC6C509)) + (w * p2) # t1
      p3 = Machine.f64(Machine.word(0xBF41A6109C73E0EC)) + (w * Machine.f64(0x3F35FD3EE8C2D3F4)) # t11 + w*t14
      p3 = Machine.f64(0x3F6282D32E15C915) + (w * p3) # t8
      p3 = Machine.f64(Machine.word(0xBF851F9FBA91EC6A)) + (w * p3) # t5
      p3 = Machine.f64(0x3FB08B4294D5419B) + (w * p3) # t2
      p = (z * p1) - (Machine.f64(Machine.word(0xBC50C7CAA48A971F)) - (w * (p2 + (y * p3)))) # tt
      return Machine.f64(Machine.word(0xBFBF19B9BCC38A42)) + p # tf
    end
    p1 = Machine.f64(0x3FCD4EAEF6010924) + (y * Machine.f64(0x3F8B678BBF2BAB09)) # u4 + y*u5
    p1 = Machine.f64(0x3FEF497644EA8450) + (y * p1) # u3
    p1 = Machine.f64(0x3FF7475CD119BD6F) + (y * p1) # u2
    p1 = Machine.f64(0x3FE4401E8B005DFF) + (y * p1) # u1
    p1 = y * (Machine.f64(Machine.word(0xBFB3C467E37DB0C8)) + (y * p1)) # u0
    p2 = Machine.f64(0x3FBAAE55D6537C88) + (y * Machine.f64(0x3F6A5ABB57D0CF61)) # v4 + y*v5
    p2 = Machine.f64(0x3FE89DFBE45050AF) + (y * p2) # v3
    p2 = Machine.f64(0x40010725A42B18F5) + (y * p2) # v2
    p2 = Machine.f64(0x4003A5D7C2BD619C) + (y * p2) # v1
    p2 = Machine.f64(0x3FF0000000000000) + (y * p2)
    (-half * y) + (p1 / p2)
  end
end
