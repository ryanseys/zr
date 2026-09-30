# Array#zip with a block on Integer arrays. The block params `a` and
# `b` shadow outer String locals of the same names. The block only
# counts, and does not read the params.

a = "ha"
b = "hb"
puts a
puts b
foo = [1, 2, 3]
bar = [10, 20, 30]
n = 0
foo.zip(bar) { |a, b| n = n + 1 }
puts n   # 3
