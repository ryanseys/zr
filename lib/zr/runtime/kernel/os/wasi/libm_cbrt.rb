# cbrt, ported from musl 1.2.5's cbrt.c (from FreeBSD; Copyright (C) 1993
# by Sun Microsystems, Inc.; optimized by Bruce D. Evans). See
# THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # cbrt(3).
  #: (f64) -> f64
  def cbrt(x)
    hx = zr_libm_high(x) & 0x7FFFFFFF
    # cbrt(NaN, INF) is itself.
    return x + x if hx >= 0x7FF00000

    # A rough cbrt to 5 bits: cbrt(2**e*(1+m) ~= 2**(e/3)*(1+(e%3+m)/3).
    # For a finite positive normal value, the integer division of its
    # bits gives almost exactly the right side, with the exponent bias
    # taken away first and put back later. The bias -0.03306235651 of the
    # (e%3+m)/3 term is in B1 and B2.
    if hx < 0x00100000
      # Zero or subnormal.
      hx = zr_libm_high(x * Machine.f64(0x4350000000000000)) & 0x7FFFFFFF # 0x1p54
      # cbrt(0) is itself.
      return x if hx == 0

      hx = (hx / 3) + 696219795 # B2 = (1023-1023/3-54/3-0.03306235651)*2**20
    else
      hx = (hx / 3) + 715094163 # B1 = (1023-1023/3-0.03306235651)*2**20
    end
    t = Machine.f64((zr_libm_bits(x) & 0x8000000000000000) | (Machine.ptr(hx) << 32))
    # A new cbrt to 23 bits: cbrt(x) = t*cbrt(x/t**3) ~= t*P(t**3/x), with
    # P of degree 4, which approximates 1/cbrt(r) to within 2**-23.5 when
    # |r - 1| < 1/10.
    r = (t * t) * (t / x)
    t *= (Machine.f64(0x3FFE03E60F61E692) + (r * (Machine.f64(Machine.word(0xBFFE28E092F02420)) + (r * Machine.f64(0x3FF9F1604A49D6C2))))) +
         ((r * r) * r * (Machine.f64(Machine.word(0xBFE844CBBEE751D9)) + (r * Machine.f64(0x3FC2B000D4E4EDD7))))
    # Round t away from zero to 23 bits, so that the result is larger in
    # magnitude than cbrt(x), but by not much more than 2 23-bit ulps.
    t = Machine.f64(Machine.uadd_wrap(zr_libm_bits(t), Machine.ptr(0x80000000)) & 0xFFFFFFFFC0000000)
    # One step of Newton's iteration to 53 bits, error < 0.667 ulps.
    s = t * t # exact
    r = x / s # error <= 0.5 ulps; |r| < |t|
    w = t + t # exact
    r = (r - t) / (w + r) # r-t is exact; w+r ~= 3*t
    t + (t * r) # error <= 0.5 + 0.5/3 + epsilon
  end
end
