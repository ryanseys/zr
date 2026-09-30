# Nested inlined blocks (block within block) with a non-local return.
def nested_blocks_return
  proc { [1, 2].each { |a| [3, 4].each { |b| return a * b if a == 2 && b == 4 } }; 0 }.call
end
p nested_blocks_return

