module Zr::Kern
  # A wasm32 module calls no C, so no C call gives it arguments to read.
  VA_LIST_BYTES = 8

  #: (ptr, ptr) -> void
  def zr_va_start(list, first)
    zr_bug(Machine.bytes("a wasm32 module has no C arguments\n"), 35)
  end

  #: (ptr, ptr) -> void
  def zr_va_from_c(list, ap)
    zr_bug(Machine.bytes("a wasm32 module has no C arguments\n"), 35)
  end

  #: (ptr) -> word
  def zr_va_next_word(list)
    zr_bug(Machine.bytes("a wasm32 module has no C arguments\n"), 35)
    0
  end

  #: (ptr) -> f64
  def zr_va_next_double(list)
    zr_bug(Machine.bytes("a wasm32 module has no C arguments\n"), 35)
    Machine.f64(0)
  end
end
