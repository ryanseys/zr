# Enumerable#find_index with block returns the index
# of the first element where the block is truthy, nil otherwise.
puts [1, 2, 3, 2].find_index { |x| x > 2 }
puts [1, 2, 3].find_index { |x| x > 10 }.inspect
