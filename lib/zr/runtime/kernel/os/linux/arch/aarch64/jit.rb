module Zr::Kern
  # Flushes the instruction cache for bytes that the JIT wrote.
  #: (ptr, word) -> void
  def zr_os_jit_flush(at, len)
    Libc.__clear_cache(at, at + len)
  end
end
