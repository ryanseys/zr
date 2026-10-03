module Zr::Kern
  # The WASI part of code loading. A module cannot map code or look up a
  # symbol, so the eval compiler (JIT) has no memory to write into.
  RTLD_DEFAULT = 0

  #: (value) -> value
  def zr_os_jit_reserve(size)
    Machine.value(QNIL)
  end

  #: (value, value) -> value
  def zr_os_jit_release(at, size)
    Machine.value(QNIL)
  end

  #: (value, value, value) -> value
  def zr_os_jit_map(size, exec, hint)
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_os_symbol(name)
    Machine.value(QNIL)
  end

  #: (value, value) -> value
  def zr_os_jit_write(at, bytes)
    zr_notimplement(Machine.bytes("mmap"), 4)
  end

  # A module cannot load a library.
  #: () -> ptr
  def zr_os_libffi_path
    Machine.bytes("\0")
  end
end
