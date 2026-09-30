# frozen_string_literal: true

# `for` performs NO type dispatch -- ruby compiles it to `coll.each { |x|
# ... }` -- and it opens NO scope: the index is a name of the body
# around it and outlives the loop. `redo` runs the body again without
# stepping, and a block-local is a name the block alone can see.

for i in 1..3
  print i
end
puts
p i

for a, b in [[1, 2], [3, 4]]
  p [a, b]
end
p [a, b]

pairs = []
for key, value in { one: 1, two: 2 }
  pairs << [key, value]
end
p pairs, key, value

