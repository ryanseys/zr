stat = {}
count = {}
2.times do
  GC.start
  GC.stat(stat)
  ObjectSpace.count_objects(count)
  GC.stat(stat)
  ObjectSpace.count_objects(count)
end
p count[:TOTAL] - count[:FREE] == stat[:heap_live_slots]
p count[:FREE] == stat[:heap_free_slots]
p count[:TOTAL] == stat[:heap_available_slots]
p stat[:total_freed_objects] >= 0
p stat[:total_allocated_objects] >= stat[:heap_live_slots]

h = {}
p GC.stat(h).equal?(h)
p GC.stat(:heap_live_slots).is_a?(Integer)
begin
  GC.stat({}.freeze)
rescue FrozenError => e
  p e.message
end
