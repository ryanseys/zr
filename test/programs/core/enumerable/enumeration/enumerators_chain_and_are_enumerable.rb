# Chaining: with_index/each_with_index wrap (blockless) and drive
# (block-given), an Enumerator is itself Enumerable (reduce/sort/select
# arrive via the real ancestor chain), and with_object threads its memo.

e = ["a", "b", "c"].each_with_index
p e.class
p e.to_a
p [10, 20].map.with_index { |x, i| x * i }
p [10, 20].each.with_index(5).to_a
p [4, 2, 6].each.reduce { |a, b| a + b }
p [4, 2, 6].each.sort
p [1, 2, 3, 4].each.select { |x| x.even? }
p [1, 2].each.with_object([]) { |x, memo| memo << x * 2 }
