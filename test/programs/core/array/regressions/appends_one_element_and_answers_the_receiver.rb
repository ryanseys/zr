# `arr << x` is also an expression, not only a statement. It appends
# and gives the receiver.
#
# In `(arr << x) << y`, the inner `<<` gives the receiver, and the
# outer `<<` appends to it again.

ints = [1]
(ints << 2) << 3
puts ints.length    # 3
puts ints[0]        # 1
puts ints[1]        # 2
puts ints[2]        # 3

floats = [1.5]
(floats << 2.5) << 3.5
puts floats.length  # 3
puts floats[2]      # 3.5

strs = ["a"]
(strs << "b") << "c"
puts strs.length    # 3
puts strs[2]        # c

syms = [:x]
(syms << :y) << :z
puts syms.length    # 3
puts syms[2]        # z
