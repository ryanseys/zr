module Zr::Kern
  # The parts of wasi-libc that ruby behavior shows: the sort, which sets
  # the order of equal elements. ruby.wasm's order is different from both
  # darwin's and musl's. zr does not copy it yet, so a module sorts as
  # darwin does.
  #: (ptr, word) -> void
  def zr_os_sort(st, n)
    zr_sort_range(st, 0, n)
  end

  # ruby_qsort: a module runs no C extension.
  #: (ptr, word, word, ptr, word) -> void
  def zr_os_c_qsort(base, nel, size, cmp, data)
    Libc.abort()
  end

  # fdopen(3): a module runs no C extension, which alone asks for one.
  #: (i32, ptr) -> ptr
  def zr_os_fdopen(fd, mode)
    Machine.ptr(0)
  end

  # memmem, which the allocator layer does not supply. Returns the first
  # position of the `m` bytes of `needle` in the `n` bytes at `hay`, or 0.
  #: (ptr, word, ptr, word) -> ptr
  def memmem(hay, n, needle, m)
    if m == 0
      return hay
    end
    i = 0
    while i + m <= n
      if zr_bytes_eq(hay + i, m, needle, m)
        return hay + i
      end
      i += 1
    end
    Machine.ptr(0)
  end

  # SHA-256 of whole blocks with the host's code. WASI has no such code to
  # call, so lib/zr/runtime/kernel/digest.rb compresses the blocks itself.
  #: (ptr, ptr, word) -> bool
  def zr_os_sha256_blocks(h, p, n)
    false
  end
end
