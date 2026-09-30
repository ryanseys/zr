# Many sequential calls: each non-local return (and each fall-through) pops its
# frame, so the bounded frame stack never overflows.
def doubled(x)
  proc { return x * 2 }.call
  -1
end
def maybe(x)
  proc { return 100 if x.even? }.call
  1
end
td = 0; ts = 0
500.times { |i| td += doubled(i); ts += maybe(i) }
p td
p ts

