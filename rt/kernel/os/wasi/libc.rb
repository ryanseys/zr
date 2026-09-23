# wasi-libc, where ruby shows it: the sort whose order decides a sort's
# ties. ruby.wasm's order is neither darwin's nor musl's; until it is
# followed, a module sorts as darwin does.
sig [Ptr, Word] => Void
machine def zr_os_sort(st, n)
  zr_sort_range(st, 0, n)
end

# The bytes a malloc'd block holds, which the heap counts as payload:
# none here, since the module's floor frees nothing (a bump heap), so
# the count only climbs and the limit doubles with it.
sig [Ptr] => Word
machine def zr_os_malloc_size(p)
  0
end

# memmem, which the floor does not answer: the first `m` bytes of
# `needle` in the `n` at `hay`, or 0.
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

# SHA-256 of whole blocks by the host's own code: there is none to call
# here, so rt/kernel/digest.rb compresses them itself.
sig [Ptr, Ptr, Word] => Bool
machine def zr_os_sha256_blocks(h, p, n)
  false
end
