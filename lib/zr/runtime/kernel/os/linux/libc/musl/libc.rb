module Zr::Kern
  # The parts of musl that ruby behavior shows. qsort_r sets the order of
  # equal elements in a sort. musl's qsort_r is smoothsort
  # (kernel/libc/musl/smoothsort.rb).
  #: (ptr, word) -> void
  def zr_os_sort(st, n)
    zr_smoothsort(st, n)
  end

  # ruby_qsort: musl's qsort_r takes C's comparator, `cmp(a, b, data)`,
  # as ruby gives it.
  #: (ptr, word, word, ptr, word) -> void
  def zr_os_c_qsort(base, nel, size, cmp, data)
    Libc.qsort_r(base, nel, size, cmp, data)
  end

  # fdopen(3): a stdio FILE on the descriptor `fd`.
  #: (i32, ptr) -> ptr
  def zr_os_fdopen(fd, mode)
    Libc.fdopen(fd, mode)
  end

  # The usable size of a malloc'd block. The heap counts it as payload.
  #: (ptr) -> word
  def zr_os_malloc_size(p)
    Libc.malloc_usable_size(p)
  end

  # SHA-256 of whole blocks with the host's code. Linux has no such code to
  # call, so lib/zr/runtime/kernel/digest.rb compresses the blocks itself.
  #: (ptr, ptr, word) -> bool
  def zr_os_sha256_blocks(h, p, n)
    false
  end

  #: () -> value
  def zr_os_issetugid
    zr_bool(Libc.issetugid() != Machine.i32(0))
  end

  # A name that the binary's own symbol table does not define. musl's
  # dlsym finds nothing in a static binary, so there is none.
  #: (value) -> value
  def zr_os_symbol_loaded(name)
    Machine.value(QNIL)
  end

  # RUBY_PLATFORM, as ruby built against musl gives it: the architecture
  # (`n` bytes at `arch`), then "-linux-musl".
  #: (ptr, word) -> value
  def zr_os_platform(arch, n)
    b = Machine.slot(32)
    zr_memcpy(b, arch, n)
    zr_memcpy(b + n, Machine.bytes("-linux-musl"), 11)
    zr_str_new(b, n + 11)
  end

  # Math.cbrt: the libm's cbrt, as ruby gives it here.
  #: (f64) -> f64
  def zr_os_cbrt(x)
    Libc.cbrt(x)
  end
end
