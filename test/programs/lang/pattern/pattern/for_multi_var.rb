# `for a, b in coll` destructures each element into multiple LVs.
for a, b in [[1, 2], [3, 4]]
  puts "#{a}, #{b}"
end

for x, y, z in [[1, 2, 3], [4, 5, 6]]
  puts "#{x},#{y},#{z}"
end
