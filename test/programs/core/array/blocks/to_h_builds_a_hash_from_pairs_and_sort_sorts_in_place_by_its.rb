# Array#to_h builds a hash from [key, value] pairs. The test checks
# lookups + length, not the hash #inspect format.
h1 = [[:a, 1], [:b, 2], [:c, 3]].to_h
p h1[:a]
p h1[:c]
p h1.length
h2 = [["x", 10], ["y", 20]].to_h
p h2["x"]
p h2["y"]
h3 = [[1, "one"], [2, "two"]].to_h
p h3[1]
p h3[2]

# Array#sort! with a comparator block sorts in place (the block's <=>
# return drives the order), not in the default ascending order.
a = [3, 1, 4, 1, 5]
a.sort! { |x, y| y <=> x }
p a
b = [3, 1, 4, 1, 5]
b.sort! { |x, y| x <=> y }
p b
s = ["bb", "a", "ccc"]
s.sort! { |x, y| x.length <=> y.length }
p s
