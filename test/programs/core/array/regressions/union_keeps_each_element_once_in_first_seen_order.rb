# Array#union for typed arrays (int/sym/str/float).
# Mirrors Array#intersection (c31b618). Returns a new array with all
# unique elements from `self` followed by unique elements from `other`.

# Integer array
puts [1, 2, 3].union([3, 4, 5]).inspect
puts [1, 2].union([3, 4]).inspect
puts [1, 2, 3].union([1, 2, 3]).inspect
puts [].union([1, 2]).inspect
puts [1, 2].union([]).inspect
puts [1, 1, 2].union([2, 3]).inspect
puts [].union([]).inspect

# String array
puts ["a", "b"].union(["b", "c"]).inspect
puts ["x"].union(["y", "z"]).inspect
puts ["a", "b", "c"].union(["a", "b", "c"]).inspect
puts ["a", "a", "b"].union(["b", "c"]).inspect

# float_array
puts [1.0, 2.0].union([2.0, 3.0]).inspect
puts [1.5, 2.5].union([3.5]).inspect
puts [1.0, 1.0, 2.0].union([2.0, 3.0]).inspect

# Symbol array
puts [:a, :b].union([:b, :c]).inspect
puts [:x].union([:y, :z]).inspect
puts [:a, :a, :b].union([:b, :c]).inspect
