# `arr.values_at(i, j, ...)` picks elements at the given indices and
# returns a fresh array of the same element type, for each kind of
# array.

# Symbol array
puts [:a, :b, :c].values_at(0, 2).inspect

# Integer array
puts [1, 2, 3, 4, 5].values_at(0, 2, 4).inspect

# String array
puts ["x", "y", "z"].values_at(1).inspect

# Single index, multiple of same value.
puts [10, 20, 30].values_at(1, 1, 1).inspect
