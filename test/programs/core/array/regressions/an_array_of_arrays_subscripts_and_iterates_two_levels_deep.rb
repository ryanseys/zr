# Array of arrays (2-level nesting)
a = [[1, 2], [3, 4], [5, 6]]
puts a.length

# Iterate nested arrays
a.each { |sub|
  puts sub[0] + sub[1]
}

# String array of arrays
b = [["hello", "world"], ["foo", "bar"]]
b.each { |pair|
  puts pair.join(" ")
}

# Push to array of arrays
c = [[10, 20]]
c.push([30, 40])
c.push([50, 60])
puts c.length
c.each { |row|
  row.each { |v| print v.to_s + " " }
  puts ""
}
