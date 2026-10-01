# The parts of wasi-libc that ruby behavior shows: the sort, which sets
# the order of equal elements. ruby.wasm's order is different from both
# darwin's and musl's. zr does not copy it yet, so a module sorts as
# darwin does.
sig [Ptr, Word] => Void
machine def zr_os_sort(st, n)
  zr_sort_range(st, 0, n)
end

# The usable size of a malloc'd block, which the heap counts as payload.
# It is 0 here. The module's allocator frees nothing (a bump heap), so
# the count only increases, and the limit doubles with it.
sig [Ptr] => Word
machine def zr_os_malloc_size(p)
  0
end

# memmem, which the allocator layer does not supply. Returns the first
# position of the `m` bytes of `needle` in the `n` bytes at `hay`, or 0.
sig [Ptr, Word, Ptr, Word] => Ptr
machine def memmem(hay, n, needle, m)
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
sig [Ptr, Ptr, Word] => Bool
machine def zr_os_sha256_blocks(h, p, n)
  false
end
