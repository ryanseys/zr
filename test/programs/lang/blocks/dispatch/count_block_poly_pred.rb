# count { |x| <poly value> } tests the block value for truthiness. Any value
# works as the predicate: only nil and false count as false.
items = [1, nil, "x", false, 2, true]
p items.count { |x| x }              # truthy: 1, "x", 2, true -> 4
p items.count { |x| x.nil? }         # 1
mixed = [1, "two", 3, "four", 5]
p mixed.count { |x| x.is_a?(Integer) }
