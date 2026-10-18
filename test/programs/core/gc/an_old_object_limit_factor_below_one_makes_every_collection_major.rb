# RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR below 1.0 makes every collection a
# major one (test_gc_parameter); RUBY_GC_HEAP_REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO
# sets the limit as a share of the old objects.
GC.start
300_000.times { Object.new }
p GC.stat[:minor_gc_count] < GC.stat[:major_gc_count]
GC.disable
GC.start
p (GC.stat[:old_objects] * 0.1).to_i == GC.stat[:remembered_wb_unprotected_objects_limit]
