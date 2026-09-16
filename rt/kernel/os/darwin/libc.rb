# darwin's libc, where ruby shows it: qsort_r, whose order decides a
# sort's ties. Libc's BSD qsort is the one rt/kernel/sort.rb follows.
sig [Ptr, Word] => Void
machine def zr_os_sort(st, n)
  zr_sort_range(st, 0, n)
end

# The bytes a malloc'd block holds, which the heap counts as payload.
Machine.import "malloc_size", [Ptr] => Word

sig [Ptr] => Word
machine def zr_os_malloc_size(p)
  malloc_size(p)
end
