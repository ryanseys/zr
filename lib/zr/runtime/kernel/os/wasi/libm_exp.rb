# exp, expm1 and the exp core of pow, ported from musl 1.2.5's exp.c and
# pow.c (Copyright (c) 2018, Arm Limited, MIT), expm1.c and __expo2.c
# (from FreeBSD; Copyright (C) 2004 by Sun Microsystems, Inc.). See
# THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # exp(3).
  #: (f64) -> f64
  def exp(x)
    abstop = zr_libm_top12(x) & 0x7FF
    # abstop - top12(0x1p-54) >= top12(512.0) - top12(0x1p-54), unsigned.
    if abstop < 0x3C9 || abstop >= 0x408
      # Tiny x: no spurious underflow; 0 is a common input.
      return Machine.f64(0x3FF0000000000000) + x if abstop < 0x3C9

      if abstop >= 0x409
        return Machine.f64(0) if zr_libm_bits(x) == 0xFFF0000000000000
        return Machine.f64(0x3FF0000000000000) + x if abstop >= 0x7FF
        return zr_libm_uflow(0) if (zr_libm_bits(x) >> 63) != 0

        return zr_libm_oflow(0)
      end
      # Large x is a special case below.
      abstop = 0
    end
    zr_libm_exp_core(x, Machine.f64(0), 0, abstop == 0)
  end

  # sign * exp(x + xtail), with |xtail| < 2**-8/N and |xtail| <= |x|;
  # `sign_bias` is SIGN_BIAS for a negative result (pow.c's exp_inline).
  #: (f64, f64, word) -> f64
  def zr_libm_exp_inline(x, xtail, sign_bias)
    abstop = zr_libm_top12(x) & 0x7FF
    if abstop < 0x3C9 || abstop >= 0x408
      if abstop < 0x3C9
        # Tiny x: no spurious underflow; 0 is a common input.
        one = Machine.f64(0x3FF0000000000000) + x
        return sign_bias != 0 ? -one : one
      end
      if abstop >= 0x409
        # pow has handled inf and nan already.
        return zr_libm_uflow(sign_bias) if (zr_libm_bits(x) >> 63) != 0

        return zr_libm_oflow(sign_bias)
      end
      # Large x is a special case below.
      abstop = 0
    end
    zr_libm_exp_core(x, xtail, sign_bias, abstop == 0)
  end

  # The common part of exp and exp_inline: exp(x) = 2**(k/N) * exp(r),
  # x = ln2/N*k + r, with N = 128 steps in exp_data.c's table. `special`
  # is true when the scale can overflow or underflow.
  #: (f64, f64, word, bool) -> f64
  def zr_libm_exp_core(x, xtail, sign_bias, special)
    shift = Machine.f64(0x4338000000000000) # 0x1.8p52
    z = Machine.f64(0x40671547652B82FE) * x # N/ln2 * x
    # z - kd is in [-1, 1] in a rounding mode that is not to nearest.
    kd = z + shift
    ki = zr_libm_bits(kd)
    kd -= shift
    r = x + (kd * Machine.f64(Machine.word(0xBF762E42FEFA0000))) + (kd * Machine.f64(Machine.word(0xBD0CF79ABC9E3B3A)))
    r += xtail
    # 2**(k/N) ~= scale * (1 + tail).
    t = zr_libm_exp_table() + ((ki & 127) * 16)
    top = Machine.ushl_wrap(Machine.uadd_wrap(ki, Machine.ptr(sign_bias)), 45)
    tail = Machine.f64(Machine.load64(t, 0))
    # A valid scale only when -1023*N < k < 1024*N.
    sbits = Machine.uadd_wrap(Machine.ptr(Machine.load64(t, 8)), top)
    # exp(x) = 2**(k/N) * exp(r) ~= scale + scale * (tail + exp(r) - 1).
    r2 = r * r
    tmp = tail + r + (r2 * (Machine.f64(0x3FDFFFFFFFFFFDBD) + (r * Machine.f64(0x3FC555555555543C)))) +
          (r2 * r2 * (Machine.f64(0x3FA55555CF172B91) + (r * Machine.f64(0x3F81111167A4D017))))
    return zr_libm_exp_special(tmp, sbits, ki) if special

    scale = Machine.f64(sbits)
    scale + (scale * tmp)
  end

  # scale * (1 + tmp) without a rounding between, for a scale whose
  # exponent overflowed (pow.c's specialcase; exp.c's is the same for a
  # positive scale). `sbits` has the bits of the scale; the sign of the
  # 32-bit `ki` gives the direction.
  #: (f64, ptr, ptr) -> f64
  def zr_libm_exp_special(tmp, sbits, ki)
    if (ki & 0x80000000) == 0
      # k > 0: the exponent of the scale can be 460 too large.
      scale = Machine.f64(Machine.usub_wrap(sbits, Machine.ptr(1009) << 52))
      return Machine.f64(0x7F00000000000000) * (scale + (scale * tmp)) # 0x1p1009
    end
    # k < 0: the subnormal range needs care.
    sbits = Machine.uadd_wrap(sbits, Machine.ptr(1022) << 52)
    scale = Machine.f64(sbits)
    y = scale + (scale * tmp)
    if Machine.fabs(y) < Machine.f64(0x3FF0000000000000)
      # Round y to the right precision before it goes into the subnormal
      # range, to prevent a double rounding.
      one = Machine.f64(0x3FF0000000000000)
      one = -one if y < Machine.f64(0)
      lo = scale - y + (scale * tmp)
      hi = one + y
      lo = one - hi + y + lo
      y = (hi + lo) - one
      # The sign of zero.
      y = Machine.f64(sbits & 0x8000000000000000) if y == Machine.f64(0)
    end
    Machine.f64(0x0010000000000000) * y # 0x1p-1022
  end

  # expm1(3): exp(x) - 1, precise near 0.
  #: (f64) -> f64
  def expm1(x)
    # @type var k: word
    one = Machine.f64(0x3FF0000000000000)
    half = Machine.f64(0x3FE0000000000000)
    ln2_hi = Machine.f64(0x3FE62E42FEE00000)
    ln2_lo = Machine.f64(0x3DEA39EF35793C76)
    hx = zr_libm_high(x) & 0x7FFFFFFF
    sign = zr_libm_bits(x) >> 63
    # A huge or infinite x, or NaN.
    if hx >= 0x4043687A
      # |x| >= 56*ln2
      return x if x != x
      return -one if sign != 0

      return x * Machine.f64(0x7FE0000000000000) if x > Machine.f64(0x40862E42FEFA39EF) # 0x1p1023, o_threshold
    end
    c = Machine.f64(0)
    k = 0
    # Argument reduction.
    if hx > 0x3FD62E42
      # |x| > 0.5 ln2
      if hx < 0x3FF0A2B2
        # and |x| < 1.5 ln2
        if sign == 0
          hi = x - ln2_hi
          lo = ln2_lo
          k = 1
        else
          hi = x + ln2_hi
          lo = -ln2_lo
          k = -1
        end
      else
        k = Machine.to_int((Machine.f64(0x3FF71547652B82FE) * x) + (sign != 0 ? -half : half))
        t = Machine.to_f64(k)
        # t*ln2_hi is exact here.
        hi = x - (t * ln2_hi)
        lo = t * ln2_lo
      end
      x = hi - lo
      c = (hi - x) - lo
    elsif hx < 0x3C900000
      # |x| < 2**-54: return x.
      return x
    end
    # x is now in the primary range.
    hfx = half * x
    hxs = x * hfx
    r1 = one + (hxs * (Machine.f64(Machine.word(0xBFA11111111110F4)) +
                       (hxs * (Machine.f64(0x3F5A01A019FE5585) +
                               (hxs * (Machine.f64(Machine.word(0xBF14CE199EAADBB7)) +
                                       (hxs * (Machine.f64(0x3ED0CFCA86E65239) +
                                               (hxs * Machine.f64(Machine.word(0xBE8AFDB76E09C32D)))))))))))
    t = Machine.f64(0x4008000000000000) - (r1 * hfx) # 3.0
    e = hxs * ((r1 - t) / (Machine.f64(0x4018000000000000) - (x * t))) # 6.0
    # c is 0
    return x - ((x * e) - hxs) if k == 0

    e = (x * (e - c)) - c
    e -= hxs
    # exp(x) ~ 2**k (x_reduced - e + 1)
    return (half * (x - e)) - half if k == -1

    two = Machine.f64(0x4000000000000000)
    if k == 1
      return -two * (e - (x + half)) if x < -Machine.f64(0x3FD0000000000000) # -0.25

      return one + (two * (x - e))
    end
    twopk = Machine.f64(Machine.ptr(0x3FF + k) << 52) # 2**k
    if k < 0 || k > 56
      # Enough to return exp(x)-1.
      y = x - e + one
      y = k == 1024 ? y * two * Machine.f64(0x7FE0000000000000) : y * twopk
      return y - one
    end
    u = Machine.f64(Machine.ptr(0x3FF - k) << 52) # 2**-k
    return (x - e + (one - u)) * twopk if k < 20

    (x - (e + u) + one) * twopk
  end

  # exp(x)/2 for x >= log(DBL_MAX), a little better than
  # 0.5*exp(x/2)*exp(x/2) (__expo2). k = 2043 makes k*ln2 have a minimal
  # relative error, with x - k*ln2 > log(DBL_MIN).
  #: (f64, f64) -> f64
  def zr_libm_expo2(x, sign)
    # k is odd, so scale*scale overflows.
    scale = zr_libm_words((0x3FF + (2043 / 2)) << 20, 0)
    # exp(x - k ln2) * 2**(k-1)
    exp(x - Machine.f64(0x40962066151ADD8B)) * (sign * scale) * scale
  end
end
