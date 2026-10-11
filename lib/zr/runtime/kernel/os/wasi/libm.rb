# WASI's libm is not linked in, so the WASI layer defines the libm calls
# that the kernel makes. This file has frexp and ldexp (Float#round,
# Float#floor and Math.frexp use them) and the helpers of the other
# libm_*.rb files, which port musl 1.2.5's src/math (Copyright © 2005-2020
# Rich Felker, et al., MIT; see THIRD_PARTY_NOTICES.md and
# licenses/musl.txt). A WASI build of C ruby links the same musl code
# (wasi-libc), so a zr module gets the values that it gets.
#
# The ports keep musl's operations in musl's order, because a different
# order rounds differently. A uint64_t of musl is a ptr here (its `>>`
# and its comparisons are unsigned), and an operation that wraps in C
# uses Machine.uadd_wrap and the others.

module Zr::Kern
  # The bits of `x` as an unsigned word (asuint64).
  #: (f64) -> ptr
  def zr_libm_bits(x)
    Machine.ptr(Machine.bits(x))
  end

  # The sign and the biased exponent of `x`: its top 12 bits (top12).
  #: (f64) -> word
  def zr_libm_top12(x)
    Machine.word(zr_libm_bits(x) >> 52)
  end

  # The high 32 bits of `x` (GET_HIGH_WORD), from 0 to 2**32 - 1.
  #: (f64) -> word
  def zr_libm_high(x)
    Machine.word(zr_libm_bits(x) >> 32)
  end

  # The low 32 bits of `x` (GET_LOW_WORD).
  #: (f64) -> word
  def zr_libm_low(x)
    Machine.word(zr_libm_bits(x) & 0xFFFFFFFF)
  end

  # The double of the high and low 32 bits (INSERT_WORDS).
  #: (word, word) -> f64
  def zr_libm_words(hi, lo)
    Machine.f64((Machine.ptr(hi & 0xFFFFFFFF) << 32) | Machine.ptr(lo & 0xFFFFFFFF))
  end

  # `x` with its high 32 bits replaced (SET_HIGH_WORD).
  #: (f64, word) -> f64
  def zr_libm_with_high(x, hi)
    zr_libm_words(hi, zr_libm_low(x))
  end

  # `x` with its low 32 bits replaced (SET_LOW_WORD).
  #: (f64, word) -> f64
  def zr_libm_with_low(x, lo)
    zr_libm_words(zr_libm_high(x), lo)
  end

  # ±2**769 * 2**769: infinity of the sign (__math_oflow).
  #: (word) -> f64
  def zr_libm_oflow(sign)
    y = Machine.f64(0x7000000000000000) # 0x1p769
    (sign != 0 ? -y : y) * y
  end

  # ±2**-767 * 2**-767: zero of the sign (__math_uflow).
  #: (word) -> f64
  def zr_libm_uflow(sign)
    y = Machine.f64(0x1000000000000000) # 0x1p-767
    (sign != 0 ? -y : y) * y
  end

  # NaN for an argument out of the domain (__math_invalid).
  #: (f64) -> f64
  def zr_libm_invalid(x)
    (x - x) / (x - x)
  end

  # ±1 / 0: infinity of the sign (__math_divzero).
  #: (word) -> f64
  def zr_libm_divzero(sign)
    one = Machine.f64(0x3FF0000000000000)
    (sign != 0 ? -one : one) / Machine.f64(0)
  end

  # The fraction of `x` in [0.5, 1), with its power of two stored as an
  # I32 at `e`. Zero, an infinity and NaN return themselves with 0.
  #: (f64, ptr) -> f64
  def frexp(x, e)
    bits = Machine.ptr(Machine.bits(x))
    biased = Machine.word((bits >> 52) & 2047)
    shift = 0
    if biased == 0
      if x == Machine.f64(0)
        Machine.store32(e, 0, Machine.i32(0))
        return x
      end
      # A subnormal number: scale it by 2**54 into the normal range.
      bits = Machine.ptr(Machine.bits(x * Machine.f64(4850376798678024192)))
      biased = Machine.word((bits >> 52) & 2047)
      shift = 54
    end
    if biased == 2047
      Machine.store32(e, 0, Machine.i32(0))
      return x
    end
    Machine.store32(e, 0, Machine.i32(biased - 1022 - shift))
    Machine.f64(Machine.word((bits & Machine.word(0x800FFFFFFFFFFFFF)) | 0x3FE0000000000000))
  end

  # `x` times 2**`n`, rounded once, as musl's scalbn computes it: a scale
  # out of range is applied in at most three steps, each exact.
  #: (f64, i32) -> f64
  def ldexp(x, n)
    k = Machine.sword(n)
    y = x
    if k > 1023
      y = y * Machine.f64(9214364837600034816)
      k -= 1023
      if k > 1023
        y = y * Machine.f64(9214364837600034816)
        k -= 1023
        k = 1023 if k > 1023
      end
    elsif k < -1022
      # 2**-1022 * 2**53: the step keeps 53 bits, so a subnormal result
      # rounds only at the last multiply.
      y = y * Machine.f64(243194379878006784)
      k += 969
      if k < -1022
        y = y * Machine.f64(243194379878006784)
        k += 969
        k = -1022 if k < -1022
      end
    end
    y * Machine.f64(Machine.word(1023 + k) << 52)
  end
end
