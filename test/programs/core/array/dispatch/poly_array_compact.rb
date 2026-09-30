# `Array#compact` on an array with heterogeneous elements and
# possible nils returns a new array with the nils removed.

puts [1, nil, 2, nil, 3].compact.inspect

# Heterogeneous (mix of int + string + nil) still works.
a = [1, nil, "two", nil, :three, nil]
puts a.compact.inspect

# No-nil array passes through unchanged.
puts [1, 2, 3].compact.inspect
