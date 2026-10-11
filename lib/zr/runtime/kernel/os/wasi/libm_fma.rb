# fma, ported from musl 1.2.5's fma.c (musl, MIT). See
# THIRD_PARTY_NOTICES.md and licenses/musl.txt.

module Zr::Kern
  # fma.c's ZEROINFNAN: the exponent from which normalize's number is 0,
  # an infinity or NaN.
  LIBM_ZEROINFNAN = 0x7FF - 0x3FF - 52 - 1

  # Stores x as m * 2**e at `out` (m at 0, e at 8, the sign bit at 16),
  # with the top 10 bits and the last bit of m 0 (fma.c's normalize).
  #: (f64, ptr) -> void
  def zr_libm_fma_normalize(x, out)
    ix = zr_libm_bits(x)
    e = Machine.word(ix >> 52)
    sign = e & 0x800
    e &= 0x7FF
    if e == 0
      ix = zr_libm_bits(x * Machine.f64(0x43E0000000000000)) # 0x1p63
      e = Machine.word((ix >> 52) & 0x7FF)
      e = e != 0 ? e - 63 : 0x800
    end
    ix &= (Machine.ptr(1) << 52) - 1
    ix |= Machine.ptr(1) << 52
    ix <<= 1
    e -= 0x3FF + 52 + 1
    Machine.store64(out, 0, ix)
    Machine.store64(out, 8, e)
    Machine.store64(out, 16, sign)
  end

  # 1 when `x` is not 0, else 0 (C's !!x).
  #: (ptr) -> ptr
  def zr_libm_nonzero(x)
    x != 0 ? Machine.ptr(1) : Machine.ptr(0)
  end

  # fma(3): x*y + z, rounded once.
  #: (f64, f64, f64) -> f64
  def fma(x, y, z)
    # @type var rlo: ptr
    # @type var rhi: ptr
    # @type var zlo: ptr
    # @type var zhi: ptr
    # @type var d: word
    # @type var e: word
    # Normalize, so that the top 10 bits and the last bit are 0.
    n = Machine.slot(72)
    zr_libm_fma_normalize(x, n)
    zr_libm_fma_normalize(y, n + 24)
    zr_libm_fma_normalize(z, n + 48)
    xm = Machine.ptr(Machine.load64(n, 0))
    xe = Machine.load64(n, 8)
    ym = Machine.ptr(Machine.load64(n, 24))
    ye = Machine.load64(n, 32)
    zm = Machine.ptr(Machine.load64(n, 48))
    ze = Machine.load64(n, 56)
    return (x * y) + z if xe >= LIBM_ZEROINFNAN || ye >= LIBM_ZEROINFNAN

    if ze >= LIBM_ZEROINFNAN
      # z == 0
      return (x * y) + z if ze > LIBM_ZEROINFNAN

      return z
    end
    # r = x*y, 128 bits (fma.c's mul). The top 20 or 21 bits of rhi and
    # the last 2 bits of rlo are 0.
    xlo = xm & 0xFFFFFFFF
    xhi = xm >> 32
    ylo = ym & 0xFFFFFFFF
    yhi = ym >> 32
    t1 = xlo * ylo
    t2 = (xlo * yhi) + (xhi * ylo)
    t3 = xhi * yhi
    rlo = Machine.uadd_wrap(t1, Machine.ushl_wrap(t2, 32))
    rhi = t3 + (t2 >> 32) + (t1 > rlo ? Machine.ptr(1) : Machine.ptr(0))
    # Align the exponents: z <<= kz, r >>= kr, with kz+kr == d, and
    # e = e+kr (== ez-kz).
    e = xe + ye
    d = ze - e
    if d > 0
      if d < 64
        zlo = Machine.ushl_wrap(zm, Machine.ptr(d))
        zhi = zm >> Machine.ptr(64 - d)
      else
        zlo = Machine.ptr(0)
        zhi = zm
        e = ze - 64
        d -= 64
        if d == 0
          # Nothing to shift.
        elsif d < 64
          rlo = Machine.ushl_wrap(rhi, Machine.ptr(64 - d)) | (rlo >> Machine.ptr(d)) |
                zr_libm_nonzero(Machine.ushl_wrap(rlo, Machine.ptr(64 - d)))
          rhi >>= Machine.ptr(d)
        else
          rlo = Machine.ptr(1)
          rhi = Machine.ptr(0)
        end
      end
    else
      zhi = Machine.ptr(0)
      d = -d
      zlo = if d == 0
              zm
            elsif d < 64
              (zm >> Machine.ptr(d)) | zr_libm_nonzero(Machine.ushl_wrap(zm, Machine.ptr(64 - d)))
            else
              Machine.ptr(1)
            end
    end
    # Add.
    sign = Machine.load64(n, 16) ^ Machine.load64(n, 40)
    nonzero = true
    if sign == Machine.load64(n, 64)
      # r += z
      rlo = Machine.uadd_wrap(rlo, zlo)
      rhi = Machine.uadd_wrap(rhi, Machine.uadd_wrap(zhi, rlo < zlo ? Machine.ptr(1) : Machine.ptr(0)))
    else
      # r -= z
      t = rlo
      rlo = Machine.ptr(Machine.usub_wrap(rlo, zlo))
      rhi = Machine.ptr(Machine.usub_wrap(Machine.ptr(Machine.usub_wrap(rhi, zhi)), t < rlo ? Machine.ptr(1) : Machine.ptr(0)))
      if (rhi >> 63) != 0
        rlo = Machine.ptr(Machine.usub_wrap(Machine.ptr(0), rlo))
        rhi = Machine.ptr(Machine.usub_wrap(Machine.ptr(Machine.usub_wrap(Machine.ptr(0), rhi)), zr_libm_nonzero(rlo)))
        sign = sign == 0 ? 0x800 : 0
      end
      nonzero = rhi != 0
    end
    # rhi gets the top 63 bits of the result; the last bit is sticky.
    if nonzero
      e += 64
      d = Machine.clz(rhi) - 1
      # d > 0
      rhi = Machine.ushl_wrap(rhi, Machine.ptr(d)) | (rlo >> Machine.ptr(64 - d)) | zr_libm_nonzero(Machine.ushl_wrap(rlo, Machine.ptr(d)))
    elsif rlo != 0
      d = Machine.clz(rlo) - 1
      rhi = d < 0 ? (rlo >> 1) | (rlo & 1) : Machine.ushl_wrap(rlo, Machine.ptr(d))
    else
      # An exact +-0.
      return (x * y) + z
    end
    e -= d
    # Convert to double: i is in [1<<62, (1<<63)-1], and |r| in
    # [0x1p62, 0x1p63].
    i = Machine.word(rhi)
    i = -i if sign != 0
    r = Machine.to_f64(i)
    if e < -1022 - 62
      # The result is subnormal before the rounding.
      if e == -1022 - 63
        c = Machine.f64(0x43E0000000000000) # 0x1p63
        c = -c if sign != 0
        # The least normal number after the rounding. musl rounds through
        # a float to get the underflow of the target; to nearest, that is
        # +-DBL_MIN.
        return sign != 0 ? -Machine.f64(0x0010000000000000) : Machine.f64(0x0010000000000000) if r == c

        # Scaling loses one bit: another top bit makes the conversion
        # the only rounding when it is inexact.
        if Machine.ushl_wrap(rhi, 53) != 0
          i = Machine.word((rhi >> 1) | (rhi & 1) | (Machine.ptr(1) << 62))
          i = -i if sign != 0
          r = Machine.to_f64(i)
          # Remove the top bit.
          r = (Machine.f64(0x4000000000000000) * r) - c
        end
      else
        # Round only once, at the scaling.
        i = Machine.word(Machine.ushl_wrap((rhi >> 10) | zr_libm_nonzero(Machine.ushl_wrap(rhi, 54)), 10))
        i = -i if sign != 0
        r = Machine.to_f64(i)
      end
    end
    ldexp(r, Machine.i32(e))
  end
end
