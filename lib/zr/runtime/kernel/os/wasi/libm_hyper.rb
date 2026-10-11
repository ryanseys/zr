# sinh, cosh, tanh, asinh, acosh and atanh, ported from musl 1.2.5's
# sinh.c, cosh.c, tanh.c, asinh.c, acosh.c and atanh.c (musl, MIT). See
# THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # sinh(3): (exp(x) - 1/exp(x))/2 = (exp(x)-1 + (exp(x)-1)/exp(x))/2.
  #: (f64) -> f64
  def sinh(x)
    one = Machine.f64(0x3FF0000000000000)
    h = Machine.f64(0x3FE0000000000000)
    h = -h if (zr_libm_bits(x) >> 63) != 0
    absx = Machine.f64(zr_libm_bits(x) & 0x7FFFFFFFFFFFFFFF)
    w = zr_libm_high(absx)
    # |x| < log(DBL_MAX)
    if w < 0x40862E42
      t = expm1(absx)
      if w < 0x3FF00000
        # This branch prevents a spurious underflow.
        return x if w < 0x3FF00000 - (26 << 20)

        return h * ((Machine.f64(0x4000000000000000) * t) - (t * t / (t + one)))
      end
      return h * (t + (t / (t + one)))
    end
    # |x| > log(DBL_MAX) or NaN
    zr_libm_expo2(absx, Machine.f64(0x4000000000000000) * h)
  end

  # cosh(3): (exp(x) + 1/exp(x))/2 = 1 + 0.5*(exp(x)-1)*(exp(x)-1)/exp(x).
  #: (f64) -> f64
  def cosh(x)
    one = Machine.f64(0x3FF0000000000000)
    x = Machine.f64(zr_libm_bits(x) & 0x7FFFFFFFFFFFFFFF)
    w = zr_libm_high(x)
    # |x| < log(2)
    if w < 0x3FE62E42
      return one if w < 0x3FF00000 - (26 << 20)

      t = expm1(x)
      return one + (t * t / (Machine.f64(0x4000000000000000) * (one + t)))
    end
    # |x| < log(DBL_MAX)
    if w < 0x40862E42
      t = exp(x)
      return Machine.f64(0x3FE0000000000000) * (t + (one / t))
    end
    # |x| > log(DBL_MAX) or NaN
    zr_libm_expo2(x, one)
  end

  # tanh(3): (exp(2*x) - 1)/(exp(2*x) - 1 + 2).
  #: (f64) -> f64
  def tanh(x)
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    sign = zr_libm_bits(x) >> 63
    x = Machine.f64(zr_libm_bits(x) & 0x7FFFFFFFFFFFFFFF)
    w = zr_libm_high(x)
    if w > 0x3FE193EA
      # |x| > log(3)/2 ~= 0.5493 or NaN
      if w > 0x40340000
        # |x| > 20 or NaN: this branch prevents an overflow.
        t = one - (Machine.f64(0) / x)
      else
        t = expm1(two * x)
        t = one - (two / (t + two))
      end
    elsif w > 0x3FD058AE
      # |x| > log(5/3)/2 ~= 0.2554
      t = expm1(two * x)
      t /= (t + two)
    elsif w >= 0x00100000
      # |x| >= 0x1p-1022, up to 2ulp error in [0.1,0.2554]
      t = expm1(-two * x)
      t = -t / (t + two)
    else
      # |x| is subnormal.
      t = x
    end
    sign != 0 ? -t : t
  end

  # asinh(3): sign(x)*log(|x|+sqrt(x*x+1)) ~= x - x**3/6 + o(x**5).
  #: (f64) -> f64
  def asinh(x)
    one = Machine.f64(0x3FF0000000000000)
    e = Machine.word((zr_libm_bits(x) >> 52) & 0x7FF)
    s = zr_libm_bits(x) >> 63
    x = Machine.f64(zr_libm_bits(x) & 0x7FFFFFFFFFFFFFFF)
    if e >= 0x3FF + 26
      # |x| >= 0x1p26, inf or NaN
      x = log(x) + Machine.f64(0x3FE62E42FEFA39EF) # ln2
    elsif e >= 0x3FF + 1
      # |x| >= 2
      x = log((Machine.f64(0x4000000000000000) * x) + (one / (Machine.sqrt((x * x) + one) + x)))
    elsif e >= 0x3FF - 26
      # |x| >= 0x1p-26, up to 1.6ulp error in [0.125,0.5]
      x = log1p(x + (x * x / (Machine.sqrt((x * x) + one) + one)))
    end
    s != 0 ? -x : x
  end

  # acosh(3): log(x + sqrt(x*x-1)). The functions that it calls handle
  # x < 1, out of the domain.
  #: (f64) -> f64
  def acosh(x)
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    e = Machine.word((zr_libm_bits(x) >> 52) & 0x7FF)
    # |x| < 2, up to 2ulp error in [1,1.125]
    return log1p(x - one + Machine.sqrt(((x - one) * (x - one)) + (two * (x - one)))) if e < 0x3FF + 1
    # |x| < 0x1p26
    return log((two * x) - (one / (x + Machine.sqrt((x * x) - one)))) if e < 0x3FF + 26

    # |x| >= 0x1p26 or NaN
    log(x) + Machine.f64(0x3FE62E42FEFA39EF) # ln2
  end

  # atanh(3): log((1+x)/(1-x))/2 = log1p(2x/(1-x))/2 ~= x + x**3/3 + o(x**5).
  #: (f64) -> f64
  def atanh(x)
    one = Machine.f64(0x3FF0000000000000)
    two = Machine.f64(0x4000000000000000)
    half = Machine.f64(0x3FE0000000000000)
    e = Machine.word((zr_libm_bits(x) >> 52) & 0x7FF)
    s = zr_libm_bits(x) >> 63
    y = Machine.f64(zr_libm_bits(x) & 0x7FFFFFFFFFFFFFFF)
    if e < 0x3FF - 1
      # |x| < 0.5, up to 1.7ulp error; a tiny |x| stays.
      y = half * log1p((two * y) + (two * y * y / (one - y))) if e >= 0x3FF - 32
    else
      # This prevents an overflow.
      y = half * log1p(two * (y / (one - y)))
    end
    s != 0 ? -y : y
  end
end
