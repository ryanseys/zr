# Array#flatten on a deep nested mixed array and on a uniform
# array of Integer arrays (the `[[a,b],[c,d]]` form).

# Deep recursive nesting: flatten goes into each nested array,
# whatever its element type.
puts [[1, [2, [3]]]].flatten.inspect

# Heterogeneous mix of scalar + array elements.
puts [1, "two", [3, [:four, 5.0]]].flatten.inspect

# Uniform [[int...]] flattens to an array of Integers.
puts [[1, 2], [3, 4], [5]].flatten.inspect

# Empty array.
puts [].flatten.inspect
