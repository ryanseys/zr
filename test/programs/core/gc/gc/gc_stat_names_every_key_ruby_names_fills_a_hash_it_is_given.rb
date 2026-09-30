# GC.stat answers every key CRuby's collector names, in its order, fills a
# Hash it is given, and refuses a key it does not know.
stats = GC.stat
p stats.keys
p stats.values.all?(Integer)
p stats[:heap_available_slots] >= stats[:heap_live_slots]
p stats[:total_allocated_objects] >= stats[:total_freed_objects]
into = {}
p GC.stat(into).equal?(into), into.size == stats.size
p GC.stat(:count).class
p((GC.stat(:nope) rescue $!))
p((GC.stat("count") rescue $!))

