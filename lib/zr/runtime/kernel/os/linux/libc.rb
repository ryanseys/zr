# The parts of musl that ruby behavior shows. qsort_r sets the order of
# equal elements in a sort. musl's qsort_r is smoothsort (smoothsort.rb
# in this directory).
sig [Ptr, Word] => Void
machine def zr_os_sort(st, n)
  zr_smoothsort(st, n)
end

# The usable size of a malloc'd block. The heap counts it as payload.
Machine.import "malloc_usable_size", [Ptr] => Word

sig [Ptr] => Word
machine def zr_os_malloc_size(p)
  malloc_usable_size(p)
end

# SHA-256 of whole blocks with the host's code. Linux has no such code to
# call, so lib/zr/runtime/kernel/digest.rb compresses the blocks itself.
sig [Ptr, Ptr, Word] => Bool
machine def zr_os_sha256_blocks(h, p, n)
  false
end
