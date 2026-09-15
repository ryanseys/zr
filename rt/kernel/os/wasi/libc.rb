# wasi-libc, where ruby shows it: the sort whose order decides a sort's
# ties. ruby.wasm's order is neither darwin's nor musl's; until it is
# followed, a module sorts as darwin does.
sig [Ptr, Word] => Void
machine def zr_os_sort(st, n)
  zr_sort_range(st, 0, n)
end
