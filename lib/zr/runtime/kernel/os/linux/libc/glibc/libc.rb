module Zr::Kern
  # The parts of glibc that ruby behavior shows. qsort_r sets the order of
  # equal elements in a sort, and its algorithm changed between releases
  # (a merge sort, then introsort in 2.37 and 2.38, then a merge sort
  # again). So the sort calls the qsort_r of the glibc that the program
  # runs on, as ruby does, and the order is that ruby's on the same system.
  #: (ptr, word) -> void
  def zr_os_sort(st, n)
    Libc.qsort_r(Sort[st].base, n, Sort[st].stride, Machine.addr(:zr_glibc_qsort_cmp), Machine.word(st))
  end

  # qsort_r calls this C-entry def with two records and the sort. A
  # comparison that raises does not unwind through glibc's frames: it
  # marks the sort failed, and each later comparison answers 0
  # (zr_sort_cmp_values).
  #: (ptr, ptr, ptr) -> i32
  def zr_glibc_qsort_cmp(a, b, st)
    Machine.gates_enter
    Machine.i32(zr_sort_cmp_values(st, Machine.value(Machine.load64(a, 0)), Machine.value(Machine.load64(b, 0))))
  end

  # ruby_qsort: glibc's qsort_r takes C's comparator, `cmp(a, b, data)`,
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

  # glibc has no issetugid: the kernel's AT_SECURE says the same.
  AT_SECURE = 23

  #: () -> value
  def zr_os_issetugid
    zr_bool(Libc.getauxval(AT_SECURE) != 0)
  end

  # A name that the binary's own symbol table does not define: libc's and
  # the other shared objects' names, which the dynamic loader knows.
  #: (value) -> value
  def zr_os_symbol_loaded(name)
    at = Machine.word(Libc.dlsym(Machine.ptr(RTLD_DEFAULT), RString[name].ptr))
    at == 0 ? Machine.value(QNIL) : zr_fix(at)
  end

  # RUBY_PLATFORM, as ruby built against glibc gives it: the architecture
  # (`n` bytes at `arch`), then "-linux".
  #: (ptr, word) -> value
  def zr_os_platform(arch, n)
    b = Machine.slot(32)
    zr_memcpy(b, arch, n)
    zr_memcpy(b + n, Machine.bytes("-linux"), 6)
    zr_str_new(b, n + 6)
  end
end
