# CRuby keeps a Symbol that the program makes at run time as a heap
# object, which count_objects counts under T_SYMBOL. zr keeps every
# Symbol in its symbol table, outside the heap, so count_objects has no
# T_SYMBOL and its TOTAL stays the count of the heap's cells.
:"made#{rand(1)}at run time"
p ObjectSpace.count_objects.key?(:T_SYMBOL)
