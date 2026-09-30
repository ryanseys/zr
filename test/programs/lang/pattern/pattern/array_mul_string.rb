# `Array * sep` (String arg) is equivalent to Array#join(sep) and
# returns a string. It does not repeat the array.
puts ([1, 2, 3] * ",")
puts ([1, 2, 3] * ",").inspect
puts ([1, 2, 3] * "")
puts (["a", "b", "c"] * "-")
