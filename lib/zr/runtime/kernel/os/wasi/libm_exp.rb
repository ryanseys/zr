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
end
