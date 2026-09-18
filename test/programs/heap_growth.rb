# The heap grows past its first arena, and stays correct.
pairs = []
120_000.times { |i| pairs << [i, i.to_s] }
puts pairs.size
puts pairs[119_999].inspect
puts pairs.sum { |i, _| i }

table = {}
60_000.times { |i| table[i] = "x#{i}" }
puts table.size
puts table[59_999]

nested = (1..40_000).map { |i| { i => [i] } }
puts nested.last
puts GC.count > 0

GC.start
puts GC.stat[:heap_live_slots] > 200_000
puts Class.new(Array).superclass

pairs = nil
table = nil
nested = nil
GC.start
puts GC.stat[:heap_live_slots] < 100_000
