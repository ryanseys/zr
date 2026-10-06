# Allocation and collection under the linked runtime: the heap survives a
# forced collection and the surviving objects keep their contents.
kept = []
2000.times { |i| kept << "row #{i}" if (i % 200).zero? }
20_000.times { "garbage".dup }
GC.start
p kept
puts kept.size
