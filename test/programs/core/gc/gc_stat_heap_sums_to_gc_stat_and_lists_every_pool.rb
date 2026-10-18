# GC.stat_heap lists as many pools as GC::INTERNAL_CONSTANTS[:HEAP_COUNT],
# and its numbers sum to GC.stat's, as both read the same counters and
# neither allocates (test_gc.rb, test_stat_heap_constraints).
stat = GC.stat
heap = GC.stat_heap
2.times do
  GC.stat(stat)
  GC.stat_heap(nil, heap)
end
sum = Hash.new(0)
heap.each_value { |pool| pool.each { |key, value| sum[key] += value } }
%i[heap_live_slots heap_free_slots heap_final_slots heap_eden_pages total_allocated_objects total_freed_objects].each do |key|
  p [key, stat[key] == sum[key]]
end
p stat[:heap_available_slots] == sum[:heap_eden_slots]
p heap.size == GC::INTERNAL_CONSTANTS[:HEAP_COUNT]
p heap.keys == (0...GC::INTERNAL_CONSTANTS[:HEAP_COUNT]).to_a
p heap.values.map { |pool| pool[:slot_size] }.each_cons(2).all? { |a, b| a < b }
p(begin
  GC.stat_heap(GC::INTERNAL_CONSTANTS[:HEAP_COUNT])
rescue ArgumentError => e
  e.message
end)
p GC.stat_heap(0, :slot_size) == GC.stat_heap(0)[:slot_size]
p GC.stat[:heap_allocated_pages] >= GC.stat[:heap_eden_pages] + GC.stat[:heap_empty_pages]
