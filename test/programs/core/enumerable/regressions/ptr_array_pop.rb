# `Array#pop` on a nested array (an Array of Integer Arrays) removes
# the last element, and a later push adds to the array.

a = [[1, 2]]
puts "before pop: #{a.inspect}"
a.pop
puts "after  pop: #{a.inspect}"
a.push([3, 4])
puts "after push: #{a.inspect}"

# Seed-and-pop idiom: array typed as Array<String> via the seed,
# then drained and used as an accumulator.
b = ["seed"]
b.pop
b.push("real")
b.push("data")
puts b.inspect

# Multiple pops drain the array.
c = [[10], [20], [30]]
c.pop
c.pop
puts c.length
