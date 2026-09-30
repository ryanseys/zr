# Array#each_with_index on an Integer array. The block params `i` and
# `j` shadow outer String locals of the same names. The outer locals
# keep their values. The block does not read the params.

i = "hi"
j = "ho"
puts i
puts j
foo = [10, 20, 30]
n = 0
foo.each_with_index { |i, j| n = n + 1 }
puts n   # 3
