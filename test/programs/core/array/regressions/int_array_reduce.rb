# Array#inject and Array#reduce are aliases. The test calls both, so
# a difference between them shows. The block param `i` shadows an
# outer String local of the same name and does not change it.

i = "hi"
puts i

foo = [1, 2, 3, 4, 5]
sum_inject = foo.inject(0) { |acc, i| acc + i }
puts sum_inject   # 15

sum_reduce = foo.reduce(0) { |acc, i| acc + i }
puts sum_reduce   # 15
