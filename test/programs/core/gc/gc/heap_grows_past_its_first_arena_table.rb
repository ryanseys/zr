# The arena table doubles when full, so a heap of more arenas than the
# table first held (64 arenas of 8,192 cells) keeps every object, and
# the count of slots follows.
# A collection at every allocation (ZR_GC_STRESS) checks the roots over
# a heap small enough to finish.
n = ENV["ZR_GC_STRESS"] ? 20_000 : 700_000
strings = Array.new(n) { |i| i.to_s }
before = GC.stat[:heap_available_slots]
p strings.size == n, strings[0], strings[n / 2] == (n / 2).to_s, strings[-1] == (n - 1).to_s
p strings.each_with_index.all? { |s, i| s == i.to_s }
p GC.stat[:heap_available_slots] >= before
strings = nil
GC.start
p GC.stat[:count] > 0

