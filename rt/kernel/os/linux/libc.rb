# musl, where ruby shows it: qsort_r, whose order decides a sort's ties.
# musl's is smoothsort (smoothsort.rb beside this file).
sig [Ptr, Word] => Void
machine def zr_os_sort(st, n)
  zr_smoothsort(st, n)
end

# The bytes a malloc'd block holds, which the heap counts as payload.
Machine.import "malloc_usable_size", [Ptr] => Word

sig [Ptr] => Word
machine def zr_os_malloc_size(p)
  malloc_usable_size(p)
end

# SHA-256 of whole blocks by the host's own code: there is none to call
# here, so rt/kernel/digest.rb compresses them itself.
sig [Ptr, Ptr, Word] => Bool
machine def zr_os_sha256_blocks(h, p, n)
  false
end
