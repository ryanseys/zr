# musl, where ruby shows it: qsort_r, whose order decides a sort's ties.
# musl's is smoothsort (smoothsort.rb beside this file).
sig [Ptr, Word] => Void
machine def zr_os_sort(st, n)
  zr_smoothsort(st, n)
end
