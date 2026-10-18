# GC.latest_gc_info(:weak_references_count) counts the objects that hold
# weak references: each live WeakMap, empty or not, and none after it
# goes (test_gc.rb, test_latest_gc_info_weak_references_count).
GC.disable
COUNT = 2_000
GC.start
before = GC.latest_gc_info(:weak_references_count)
maps = Array.new(COUNT) { ObjectSpace::WeakMap.new }
keys = Array.new(10) { Object.new }
keys.each { |key| maps[0][key] = key }
GC.start
held = GC.latest_gc_info(:weak_references_count)
p held >= before + COUNT - 100
p held.is_a?(Integer)
maps.clear
maps = nil
GC.start
p GC.latest_gc_info(:weak_references_count) <= held - COUNT + 100
p GC.latest_gc_info[:weak_references_count] == GC.latest_gc_info(:weak_references_count)
