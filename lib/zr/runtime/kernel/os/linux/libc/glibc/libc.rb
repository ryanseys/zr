module Zr::Kern
  # The parts of glibc that ruby behavior shows. qsort_r sets the order of
  # equal elements in a sort. glibc's qsort_r is a stable top-down merge
  # sort (stdlib/msort.c) in every release; zr_glibc_msort makes each
  # comparison that it makes, in the same order.
  #: (ptr, word) -> void
  def zr_os_sort(st, n)
    # The merge buffer is an Array, so the collector sees the elements
    # that a comparison's Ruby can see only there.
    words = (n * Sort[st].stride) / 8
    tmp = zr_ary_new(words)
    Libc.memset(RArray[tmp].ptr, Machine.i32(0), words * 8)
    RArray[tmp].len = words
    zr_glibc_msort(st, RArray[tmp].ptr, 0, n)
    RArray[tmp].len = 0
  end

  # Sorts the `n` records from index `b` with `tmp` for the merge, as
  # msort_with_tmp does: the first half, the second half, then a merge
  # that takes from the first half while it compares at most equal.
  #: (ptr, ptr, word, word) -> void
  def zr_glibc_msort(st, tmp, b, n)
    if n <= 1
      return
    end
    n1 = n / 2
    n2 = n - n1
    zr_glibc_msort(st, tmp, b, n1)
    zr_glibc_msort(st, tmp, b + n1, n2)
    s = Sort[st].stride
    i = b
    j = b + n1
    out = tmp
    while n1 > 0 && n2 > 0
      if zr_sort_cmp(st, i, j) <= 0
        zr_memcpy(out, Sort[st].base + (i * s), s)
        i += 1
        n1 -= 1
      else
        zr_memcpy(out, Sort[st].base + (j * s), s)
        j += 1
        n2 -= 1
      end
      out += s
    end
    if n1 > 0
      zr_memcpy(out, Sort[st].base + (i * s), n1 * s)
    end
    zr_memcpy(Sort[st].base + (b * s), tmp, (n - n2) * s)
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
