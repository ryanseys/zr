# Array#+ on arrays of different element types gives a mixed array.
# Each element keeps its own type.

a1 = [1, 2, 3]
a2 = ["x", "y", "z"]
a3 = a1 + a2
puts a3.length
puts a3[0]
puts a3[3]
puts "ok"

# Float + Int round-trip
b1 = [1.5, 2.5]
b2 = [10, 20]
b3 = b1 + b2
puts b3.length
puts b3[0]
puts b3[2]
puts "done"
