# Array#each_with_object on an Integer array. The block params `i` and
# `acc` shadow outer String locals of the same names. `acc` takes the
# Integer seed, and the outer `acc` keeps its String. The block does
# not read the params.

i = "hi"
acc = "ho"
puts i
puts acc
foo = [10, 20, 30]
n = 0
foo.each_with_object(0) { |i, acc| n = n + 1 }
puts n   # 3
