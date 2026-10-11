# erf and erfc, ported from musl 1.2.5's erf.c (from FreeBSD; Copyright
# (C) 1993 by Sun Microsystems, Inc.). See THIRD_PARTY_NOTICES.md and
# licenses/musl.txt.

module Zr::Kern
  # r/s on [0, 0.84375]: erf(x) = x + x*(r/s) there, with z = x*x.
  #: (f64) -> f64
  def zr_libm_erf_small(z)
    r = Machine.f64(Machine.word(0xBF77A291236668E4)) + (z * Machine.f64(Machine.word(0xBEF8EAD6120016AC))) # pp3 + z*pp4
    r = Machine.f64(Machine.word(0xBF9D2A51DBD7194F)) + (z * r) # pp2
    r = Machine.f64(Machine.word(0xBFD4CD7D691CB913)) + (z * r) # pp1
    r = Machine.f64(0x3FC06EBA8214DB68) + (z * r) # pp0
    s = Machine.f64(0x3F215DC9221C1A10) + (z * Machine.f64(Machine.word(0xBED09C4342A26120))) # qq4 + z*qq5
    s = Machine.f64(0x3F74D022C4D36B0F) + (z * s) # qq3
    s = Machine.f64(0x3FB0A54C5536CEBA) + (z * s) # qq2
    s = Machine.f64(0x3FD97779CDDADC09) + (z * s) # qq1
    s = Machine.f64(0x3FF0000000000000) + (z * s)
    r / s
  end

  # erfc on [0.84375, 1.25] (erfc1).
  #: (f64) -> f64
  def zr_libm_erfc1(x)
    one = Machine.f64(0x3FF0000000000000)
    s = Machine.fabs(x) - one
    p = Machine.f64(0x3FA22A36599795EB) + (s * Machine.f64(Machine.word(0xBF61BF380A96073F))) # pa5 + s*pa6
    p = Machine.f64(Machine.word(0xBFBC63983D3E28EC)) + (s * p) # pa4
    p = Machine.f64(0x3FD45FCA805120E4) + (s * p) # pa3
    p = Machine.f64(Machine.word(0xBFD7D240FBB8C3F1)) + (s * p) # pa2
    p = Machine.f64(0x3FDA8D00AD92B34D) + (s * p) # pa1
    p = Machine.f64(Machine.word(0xBF6359B8BEF77538)) + (s * p) # pa0
    q = Machine.f64(0x3F8BEDC26B51DD1C) + (s * Machine.f64(0x3F888B545735151D)) # qa5 + s*qa6
    q = Machine.f64(0x3FC02660E763351F) + (s * q) # qa4
    q = Machine.f64(0x3FB2635CD99FE9A7) + (s * q) # qa3
    q = Machine.f64(0x3FE14AF092EB6F33) + (s * q) # qa2
    q = Machine.f64(0x3FBB3E6618EEE323) + (s * q) # qa1
    q = one + (s * q)
    one - Machine.f64(0x3FEB0AC160000000) - (p / q) # erx
  end

  # erfc for |x| in [0.84375, 28) (erfc2); `ix` is the high word of |x|.
  #: (word, f64) -> f64
  def zr_libm_erfc2(ix, x)
    one = Machine.f64(0x3FF0000000000000)
    # |x| < 1.25
    return zr_libm_erfc1(x) if ix < 0x3FF40000

    x = Machine.fabs(x)
    s = one / (x * x)
    if ix < 0x4006DB6D
      # |x| < 1/.35 ~ 2.85714
      r = Machine.f64(Machine.word(0xC054526557E4D2F2)) + (s * Machine.f64(Machine.word(0xC023A0EFC69AC25C))) # ra6 + s*ra7
      r = Machine.f64(Machine.word(0xC067135CEBCCABB2)) + (s * r) # ra5
      r = Machine.f64(Machine.word(0xC0644CB184282266)) + (s * r) # ra4
      r = Machine.f64(Machine.word(0xC04F300AE4CBA38D)) + (s * r) # ra3
      r = Machine.f64(Machine.word(0xC0251E0441B0E726)) + (s * r) # ra2
      r = Machine.f64(Machine.word(0xBFE63416E4BA7360)) + (s * r) # ra1
      r = Machine.f64(Machine.word(0xBF843412600D6435)) + (s * r) # ra0
      ss = Machine.f64(0x401A47EF8E484A93) + (s * Machine.f64(Machine.word(0xBFAEEFF2EE749A62))) # sa7 + s*sa8
      ss = Machine.f64(0x405B28A3EE48AE2C) + (s * ss) # sa6
      ss = Machine.f64(0x407AD02157700314) + (s * ss) # sa5
      ss = Machine.f64(0x40842B1921EC2868) + (s * ss) # sa4
      ss = Machine.f64(0x407B290DD58A1A71) + (s * ss) # sa3
      ss = Machine.f64(0x4061350C526AE721) + (s * ss) # sa2
      ss = Machine.f64(0x4033A6B9BD707687) + (s * ss) # sa1
    else
      # |x| > 1/.35
      r = Machine.f64(Machine.word(0xC09004616A2E5992)) + (s * Machine.f64(Machine.word(0xC07E384E9BDC383F))) # rb5 + s*rb6
      r = Machine.f64(Machine.word(0xC083EC881375F228)) + (s * r) # rb4
      r = Machine.f64(Machine.word(0xC064145D43C5ED98)) + (s * r) # rb3
      r = Machine.f64(Machine.word(0xC031C209555F995A)) + (s * r) # rb2
      r = Machine.f64(Machine.word(0xBFE993BA70C285DE)) + (s * r) # rb1
      r = Machine.f64(Machine.word(0xBF84341239E86F4A)) + (s * r) # rb0
      ss = Machine.f64(0x407DA874E79FE763) + (s * Machine.f64(Machine.word(0xC03670E242712D62))) # sb6 + s*sb7
      ss = Machine.f64(0x40A3F219CEDF3BE6) + (s * ss) # sb5
      ss = Machine.f64(0x40A8FFB7688C246A) + (s * ss) # sb4
      ss = Machine.f64(0x409802EB189D5118) + (s * ss) # sb3
      ss = Machine.f64(0x40745CAE221B9F0A) + (s * ss) # sb2
      ss = Machine.f64(0x403E568B261D5190) + (s * ss) # sb1
    end
    ss = one + (s * ss)
    z = zr_libm_with_low(x, 0)
    exp((-z * z) - Machine.f64(0x3FE2000000000000)) * exp(((z - x) * (z + x)) + (r / ss)) / x # 0.5625
  end

  # erf(3).
  #: (f64) -> f64
  def erf(x)
    one = Machine.f64(0x3FF0000000000000)
    ix = zr_libm_high(x)
    sign = ix >> 31
    ix &= 0x7FFFFFFF
    # erf(nan)=nan, erf(+-inf)=+-1
    return Machine.to_f64(1 - (2 * sign)) + (one / x) if ix >= 0x7FF00000

    if ix < 0x3FEB0000
      # |x| < 0.84375; |x| < 2**-28 does not underflow.
      if ix < 0x3E300000
        return Machine.f64(0x3FC0000000000000) * ((Machine.f64(0x4020000000000000) * x) + (Machine.f64(0x3FF06EBA8214DB69) * x)) # efx8
      end
      return x + (x * zr_libm_erf_small(x * x))
    end
    # 0.84375 <= |x| < 6
    y = ix < 0x40180000 ? one - zr_libm_erfc2(ix, x) : one - Machine.f64(0x0010000000000000) # 0x1p-1022
    sign != 0 ? -y : y
  end

  # erfc(3).
  #: (f64) -> f64
  def erfc(x)
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    half = Machine.f64(0x3FE0000000000000)
    tiny = Machine.f64(0x0010000000000000) # 0x1p-1022
    ix = zr_libm_high(x)
    sign = ix >> 31
    ix &= 0x7FFFFFFF
    # erfc(nan)=nan, erfc(+-inf)=0,2
    return Machine.to_f64(2 * sign) + (one / x) if ix >= 0x7FF00000

    if ix < 0x3FEB0000
      # |x| < 0.84375; |x| < 2**-56 gives 1 - x.
      return one - x if ix < 0x3C700000

      y = zr_libm_erf_small(x * x)
      # x < 1/4
      return one - (x + (x * y)) if sign != 0 || ix < 0x3FD00000

      return half - (x - half + (x * y))
    end
    # 0.84375 <= |x| < 28
    if ix < 0x403C0000
      return sign != 0 ? two - zr_libm_erfc2(ix, x) : zr_libm_erfc2(ix, x)
    end
    sign != 0 ? two - tiny : tiny * tiny
  end
end
