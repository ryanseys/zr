p GC.start, GC.start(full_mark: false)
p GC.count.is_a?(Integer), GC.count > 0
p GC.disable, GC.disable, GC.enable, GC.enable
p GC.stat.class, GC.stat[:count].class, GC.stat(:heap_live_slots).class, GC.stat[:count] <= GC.count
GC.start
base = GC.stat[:heap_live_slots]
x = Array.new(1000) { "s" }
p GC.stat[:heap_live_slots] >= base + 1000
x = nil
GC.start
p GC.stat[:heap_live_slots] < base + 1000
was = GC.stress
GC.stress = true
p GC.stress
GC.stress = was
p GC.stress == was
p GC.stat[:total_allocated_objects] > 0
begin; GC.stat(:nope); rescue ArgumentError => e; puts e.message; end
p GC.respond_to?(:garbage_collect), Object.new.extend(GC).garbage_collect
