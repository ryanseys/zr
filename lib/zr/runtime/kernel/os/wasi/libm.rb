# WASI's libm is not linked in, so the kernel defines the two libm calls
# that only move the exponent. Float#round, Float#floor and Math.frexp
# use them.

module Zr::Kern
  # The fraction of `x` in [0.5, 1), with its power of two stored as an
  # I32 at `e`. Zero, an infinity and NaN return themselves with 0.
  sig [F64, Ptr] => F64
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
    Machine.f64(Machine.word((bits & 0x800FFFFFFFFFFFFF) | 0x3FE0000000000000))
  end

  # `x` times 2**`n`, rounded once, as musl's scalbn computes it: a scale
  # out of range is applied in at most three steps, each exact.
  sig [F64, I32] => F64
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
