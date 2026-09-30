# A Hash with Array keys. Each `[a, b]` literal makes a new Array, but
# two Arrays with the same elements have the same hash and are eql?.
# So a new `[a, b]` finds the entry, and `||=` does not add a second.

entries = {}
entries[[1, 2]] = "a"
entries[[3, 4]] = "b"
entries[[1, 2]] ||= "z"   # already set, no overwrite
puts entries[[1, 2]]      # "a"
puts entries[[3, 4]]      # "b"
puts entries.length       # 2

# Mixed keys also work: an Integer and an Array in one Hash.
mixed = {}
mixed[42] = "int-key"
mixed[[5, 6, 7]] = "arr-key"
mixed[[5, 6, 7]] ||= "no-overwrite"
puts mixed[42]            # int-key
puts mixed[[5, 6, 7]]     # arr-key
puts mixed.length         # 2
