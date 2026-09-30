# `min` and `max` of an empty array give nil, and inspect shows "nil".

# `[1].first(0)` gives an empty array of Integer elements.
a = [1].first(0)
puts a.min.inspect
puts a.max.inspect

# Non-empty: unchanged.
b = [3, 1, 4, 1, 5, 9, 2, 6]
puts b.min
puts b.max
