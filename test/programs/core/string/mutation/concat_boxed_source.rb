# A boxed source for #concat: the element read out of a nested array is an
# array at run time, and #concat appends its elements.
g = [[1, 2], [3, 4]]
p g.each_with_object([]) { |r, acc| acc.concat(r) }
acc2 = []
g.each { |r| acc2.concat(r) }
p acc2
s = ["a", "b"]
out = []
[s].each { |r| out.concat(r) }
p out
p [1, 2].concat([3, 4])
