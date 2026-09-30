# GC.count is the number of GCs run and GC.stat carries a :count key; after
# an explicit GC.start both must be positive.
GC.start
puts (GC.count > 0).inspect
puts GC.stat.key?(:count).inspect
puts GC.stat(:count).class
