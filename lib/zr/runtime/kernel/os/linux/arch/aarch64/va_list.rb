module Zr::Kern
  # A C call's variadic arguments on aarch64 linux: AAPCS64's va_list, a
  # struct that reads the arguments that came in registers from their
  # save areas, then the rest from the stack.
  class VaList < Layout
    attr_accessor :stack #: ptr
    attr_accessor :gr_top #: ptr
    attr_accessor :vr_top #: ptr
    attr_accessor :gr_offs #: i32
    attr_accessor :vr_offs #: i32
  end

  # A variadic function's `Machine.va_list(VA_LIST_KIND)` is one that its
  # prologue fills, with the registers that its arguments came in.
  VA_LIST_BYTES = 32
  VA_LIST_KIND = 1

  # Copies a va_list that C passed (by its address, as AAPCS64 passes the
  # array type), so the reads here do not move C's.
  #: (ptr, ptr) -> void
  def zr_va_from_c(list, ap)
    zr_memcpy(list, ap, VA_LIST_BYTES)
  end

  #: (ptr) -> word
  def zr_va_next_word(list)
    offs = Machine.sword(VaList[list].gr_offs)
    if offs < 0 && offs + 8 <= 0
      VaList[list].gr_offs = Machine.i32(offs + 8)
      return Machine.load64(VaList[list].gr_top + offs, 0)
    end
    VaList[list].gr_offs = Machine.i32(0)
    zr_va_next_stacked(list)
  end

  #: (ptr) -> f64
  def zr_va_next_double(list)
    offs = Machine.sword(VaList[list].vr_offs)
    if offs < 0 && offs + 16 <= 0
      VaList[list].vr_offs = Machine.i32(offs + 16)
      return Machine.f64(Machine.load64(VaList[list].vr_top + offs, 0))
    end
    VaList[list].vr_offs = Machine.i32(0)
    Machine.f64(zr_va_next_stacked(list))
  end

  #: (ptr) -> word
  def zr_va_next_stacked(list)
    at = VaList[list].stack
    VaList[list].stack = at + 8
    Machine.load64(at, 0)
  end
end
