# Array#select on an Integer array. The block param `i` shadows an outer
# String local of the same name. The block does not read the param,
# and gives a constant result.

i = "hi"
puts i
foo = [10, 20, 30]
all = foo.select { |i| true }
puts all.length   # 3
puts all[0]       # 10
puts all[1]       # 20
puts all[2]       # 30
none = foo.select { |i| false }
puts none.length  # 0
