# Test additional array methods

arr = Array.new
arr.push(5); arr.push(3); arr.push(8); arr.push(1)
arr.push(4); arr.push(2); arr.push(7); arr.push(6)

# count with block
puts arr.count { |x| x > 4 }   # 4 (5,8,7,6)

# count without block
puts arr.count                   # 8

# min_by / max_by
puts arr.min_by { |x| x }       # 1
puts arr.max_by { |x| x }       # 8

# sort_by
sorted = arr.sort_by { |x| -x }
puts sorted[0]    # 8
puts sorted[1]    # 7
puts sorted[7]    # 1

# String array count
words = "hello world foo bar".split(" ")
puts words.count { |w| w.length > 3 }  # 2 (hello, world)
puts words.count                         # 4

puts "done"
