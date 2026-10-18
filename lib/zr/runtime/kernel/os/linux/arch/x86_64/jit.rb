module Zr::Kern
  # x86 keeps its instruction cache coherent with the bytes that the
  # JIT wrote, so there is nothing to flush.
  #: (ptr, word) -> void
  def zr_os_jit_flush(at, len); end
end
