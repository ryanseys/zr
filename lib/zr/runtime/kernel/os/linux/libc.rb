module Zr::Kern
  # The parts of musl that ruby behavior shows. qsort_r sets the order of
  # equal elements in a sort. musl's qsort_r is smoothsort (smoothsort.rb
  # in this directory).
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
end
