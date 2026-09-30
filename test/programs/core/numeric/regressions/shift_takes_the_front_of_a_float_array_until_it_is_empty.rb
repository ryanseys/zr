arr = [1.5, 2.5, 3.5, 4.5]
puts arr.shift  # 1.5
puts arr.length # 3
puts arr[0]     # 2.5
while arr.length > 0
  puts arr.shift
end
puts arr.length # 0
