# A constant initializer's RHS can introduce block params (here `n`)
# at the top level, as in `Array#sum { |n| ... }`.

TOTAL = [1, 2, 3].sum { |n| n * 2 }
puts TOTAL                         # 12

DOUBLED = [4, 5, 6].sum { |m| m * 3 }
puts DOUBLED                       # 45
