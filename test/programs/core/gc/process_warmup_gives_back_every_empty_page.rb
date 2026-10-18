# Process.warmup frees every empty page of the heap, the spare ones a
# collection keeps for growth too, as rb_gc_prepare_heap does: after it,
# GC.stat counts no empty page, even with the collector disabled, and the
# program still allocates as before.
GC.start
ary = Array.new(100_000) { Object.new }
ary.clear
ary = nil
GC.disable
Process.warmup
p GC.stat(:heap_empty_pages), GC.stat(:total_freed_pages) > 0
GC.enable

kept = Array.new(50_000) { |i| "s#{i}" }
p kept.size, kept.last
Process.warmup
p GC.stat(:heap_empty_pages)
p kept.sum(&:size)
