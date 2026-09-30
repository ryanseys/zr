# Array#- / Array#difference must preserve LHS duplicates that
# aren't in the RHS. CRuby semantics:
#   [1, 1, 2, 3] - [3]  → [1, 1, 2]   (NOT [1, 2])
#   [1, 1, 2, 3] - [1]  → [2, 3]      (every 1 removed)

# Integer array
puts ([1, 1, 2, 3] - [3]).inspect
puts ([1, 1, 2, 3] - [1]).inspect
puts ([1, 1, 1, 2, 2] - [1]).inspect
puts ([1, 2, 1, 3, 1] - [3]).inspect

# String array
puts (["a", "a", "b", "c"] - ["c"]).inspect
puts (["a", "b", "a", "c", "a"] - ["c"]).inspect

# float_array
puts ([1.0, 1.0, 2.0, 3.0] - [3.0]).inspect
puts ([1.5, 1.5, 2.5] - [2.5]).inspect

# method form
puts [1, 1, 2, 3].difference([3]).inspect
puts ["a", "a", "b"].difference(["b"]).inspect
