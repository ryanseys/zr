# Integer array
a = [1, 2, 3, 4]
b = [3, 4, 5, 6]
puts a.intersection(b).inspect

# no common elements -> empty
puts [1, 2].intersection([3, 4]).inspect

# all in common
puts [1, 2, 3].intersection([1, 2, 3]).inspect

# duplicates in self are deduplicated
puts [1, 1, 2, 3].intersection([1, 2]).inspect

# empty self -> empty
puts [].intersection([1, 2, 3]).inspect

# empty other -> empty
puts [1, 2, 3].intersection([]).inspect

# both empty
puts [].intersection([]).inspect

# single element match
puts [42].intersection([42]).inspect

# single element no match
puts [42].intersection([99]).inspect

# String array
x = "a b c d".split(" ")
y = "c d e f".split(" ")
puts x.intersection(y).inspect

# str no common -> empty
puts "a b".split(" ").intersection("c d".split(" ")).inspect

# str all common
puts "x y".split(" ").intersection("x y".split(" ")).inspect

# str empty self
puts "".split(" ").intersection("a b".split(" ")).inspect

# str duplicates in self are deduplicated
puts "a a b c".split(" ").intersection("a b".split(" ")).inspect

# str empty other -> empty
puts "a b".split(" ").intersection("".split(" ")).inspect

# float_array
puts [1.0, 2.0, 3.0].intersection([2.0, 3.0, 4.0]).inspect

# float no common -> empty
puts [1.1, 2.2].intersection([3.3, 4.4]).inspect

# float all common
puts [1.5, 2.5].intersection([1.5, 2.5]).inspect

# float duplicates in self are deduplicated
puts [1.0, 1.0, 2.0].intersection([1.0]).inspect

# float single no match -> empty
puts [9.9].intersection([1.0, 2.0]).inspect

# Symbol array
puts [:a, :b, :c, :d].intersection([:c, :d, :e]).inspect

# sym no common -> empty
puts [:a, :b].intersection([:c, :d]).inspect

# sym all common
puts [:x, :y].intersection([:x, :y]).inspect

# sym duplicates in self are deduplicated
puts [:a, :a, :b].intersection([:a]).inspect
