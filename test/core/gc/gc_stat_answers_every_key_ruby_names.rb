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

__END__
[:count, :time, :marking_time, :sweeping_time, :heap_allocated_pages, :heap_empty_pages, :heap_allocatable_slots, :heap_available_slots, :heap_live_slots, :heap_free_slots, :heap_final_slots, :heap_marked_slots, :heap_eden_pages, :total_allocated_pages, :total_freed_pages, :total_allocated_objects, :total_freed_objects, :malloc_increase_bytes, :malloc_increase_bytes_limit, :minor_gc_count, :major_gc_count, :compact_count, :read_barrier_faults, :total_moved_objects, :remembered_wb_unprotected_objects, :remembered_wb_unprotected_objects_limit, :old_objects, :old_objects_limit, :oldmalloc_increase_bytes, :oldmalloc_increase_bytes_limit]
true
true
true
true
true
Integer
#<ArgumentError: unknown key: nope>
#<TypeError: non-hash or symbol given>
