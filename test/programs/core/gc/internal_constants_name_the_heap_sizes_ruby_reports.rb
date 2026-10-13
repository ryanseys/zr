# GC::INTERNAL_CONSTANTS names the heap sizes that ruby reports: the slot
# size as RVALUE_SIZE, and no HEAP_PAGE_OBJ_LIMIT. The values depend on the
# build, so only the names, the kinds and a relation show.
c = GC::INTERNAL_CONSTANTS
p c.keys, c.frozen?
p c.except(:DEBUG).values.all?(Integer), c[:DEBUG]
p c[:RVALUE_SIZE] > c[:RBASIC_SIZE], (c[:RVALUE_SIZE] - c[:RBASIC_SIZE]) % 8
