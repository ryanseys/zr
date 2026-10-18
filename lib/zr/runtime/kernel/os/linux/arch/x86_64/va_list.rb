module Zr::Kern
  # A C call's variadic arguments on x86_64 linux: the System V va_list,
  # which reads the arguments that came in registers from its register
  # save area (rdi..r9, then xmm0..xmm7 at 16 bytes each), then the rest
  # from the stack.
  class VaList < Layout
    attr_accessor :gp_offset #: i32
    attr_accessor :fp_offset #: i32
    attr_accessor :overflow #: ptr
    attr_accessor :saved #: ptr
  end

  # A variadic function's `Machine.va_list(VA_LIST_KIND)` is one that its
  # prologue fills, with the registers that its arguments came in.
  VA_LIST_BYTES = 24
  VA_LIST_KIND = 2

  # Copies a va_list that C passed (by its address, as System V passes
  # the array type), so the reads here do not move C's.
  #: (ptr, ptr) -> void
  def zr_va_from_c(list, ap)
    zr_memcpy(list, ap, VA_LIST_BYTES)
  end

  #: (ptr) -> word
  def zr_va_next_word(list)
    offs = Machine.u32(VaList[list].gp_offset)
    if offs < 48
      VaList[list].gp_offset = Machine.i32(offs + 8)
      return Machine.load64(VaList[list].saved + offs, 0)
    end
    zr_va_next_stacked(list)
  end

  #: (ptr) -> f64
  def zr_va_next_double(list)
    offs = Machine.u32(VaList[list].fp_offset)
    if offs < 176
      VaList[list].fp_offset = Machine.i32(offs + 16)
      return Machine.f64(Machine.load64(VaList[list].saved + offs, 0))
    end
    Machine.f64(zr_va_next_stacked(list))
  end

  #: (ptr) -> word
  def zr_va_next_stacked(list)
    at = VaList[list].overflow
    VaList[list].overflow = at + 8
    Machine.load64(at, 0)
  end
end
