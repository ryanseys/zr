module Zr::Kern
  # A C call's variadic arguments on darwin arm64. Apple's ABI passes each
  # one on the stack in 8 bytes of its own, in order, whatever its type:
  # an int's high bits mean nothing, and a double is its bits. A VaList is
  # a word with the address of the next one, which is also what C's
  # va_list is here. A variadic function's `Machine.va_list(VA_LIST_KIND)`
  # is one that its prologue starts at its first argument.
  VA_LIST_BYTES = 8
  VA_LIST_KIND = 0

  # Starts the VaList at `list` from a va_list that C passed (rb_vsprintf).
  #: (ptr, ptr) -> void
  def zr_va_from_c(list, ap)
    Machine.store64(list, 0, Machine.word(ap))
  end

  # The next argument's 64 bits, as an integer or a pointer.
  #: (ptr) -> word
  def zr_va_next_word(list)
    at = Machine.ptr(Machine.load64(list, 0))
    Machine.store64(list, 0, Machine.word(at + 8))
    Machine.load64(at, 0)
  end

  # The next argument, a double.
  #: (ptr) -> f64
  def zr_va_next_double(list)
    Machine.f64(zr_va_next_word(list))
  end
end
