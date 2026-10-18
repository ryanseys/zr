# Bug #21214: each size of cell grows on its own. After a full
# collection, the size of the short-lived objects has no room left for the
# live set of the other size.
COUNT = 1_000_000
def allocate_small_object = []
def allocate_large_object = Array.new(10)
@arys = Array.new(COUNT) do
  10.times { allocate_small_object }
  allocate_large_object
end
GC.start
available = GC.stat(:heap_available_slots)
p available < COUNT * 2
p GC.stat_heap.sum { |_, heap| heap[:heap_eden_slots] } == available
p ObjectSpace.count_objects[:TOTAL] == available
