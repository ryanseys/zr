# Array#partition (block form) gives an array that holds two arrays.
# The GC keeps the two inner arrays alive while the outer one is
# alive. After many collections, `parts[0].length` is still 3.

arr = [1, 2, 3, 4, 5, 6]
parts = arr.partition { |x| x.odd? }

# Force many GCs by allocating lots of GC-managed objects.
i = 0
while i < 200000
  tmp = [1, 2, 3]
  tmp.push(i)
  i += 1
end

puts parts[0].length   # 3
puts parts[1].length   # 3
puts "done"
