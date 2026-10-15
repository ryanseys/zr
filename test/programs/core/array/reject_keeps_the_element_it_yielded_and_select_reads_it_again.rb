# Array#reject keeps the element that it gave the block. Array#select
# and filter read the element at that index again after the block, so a
# block that changes the Array changes what select keeps.
a = [1, 2, 3, 4]
p a.reject { |x| a.shift if x == 1; x.even? }, a
a = [1, 2, 3, 4]
p a.select { |x| a.shift if x == 1; x.odd? }, a
a = [1, 2, 3, 4]
p a.filter { |x| a[0] = 9 if x == 1; true }
a = [1, 2, 3, 4]
p a.reject { |x| a[0] = 9 if x == 1; false }
a = [1, 2, 3]
p a.select { |x| a.pop(2) if x == 1; true }
a = [1, 2, 3]
p a.reject { |x| a.pop(2) if x == 1; false }
a = [1, 2]
p a.reject { |x| a << 5 if x == 1; x.even? }
