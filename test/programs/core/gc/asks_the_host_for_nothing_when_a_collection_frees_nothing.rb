# A collection that finds the same objects live as the one before
# it has nothing to say about how big the heap should be. It must
# leave the heap where it found it, and not grow it again for
# having run.

def pages = GC.stat_heap.sum { |_, pool| pool[:heap_eden_pages] }

held = Array.new(20_000) { |i| { i => "row #{i}" } }
before = pages
GC.start
puts pages <= before
puts held.size
