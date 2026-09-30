# Chained `[]=` and `[]op=` with a Symbol key, on an array element
# that is a Hash: `arr[i][:k] = v` and `arr[i][:k] += v`.
# The write changes the Hash in the array. The same is true for
# `f[:k] += v` in an each block, where `f` is each element.

# T1: direct `[]=` on an array of Hashes
arr1 = [{x: 1}]
arr1[0][:x] = 99
puts arr1[0][:x].to_s

# T2: compound `[]+=` on an array of Hashes
arr2 = [{x: 1}]
arr2[0][:x] += 100
puts arr2[0][:x].to_s

# T3: `each` block mutating each hash via `f[:k] += v`
arr3 = []
arr3 << {x: 1}
arr3 << {x: 3}
arr3.each { |f| f[:x] += 100 }
puts arr3[0][:x].to_s
puts arr3[1][:x].to_s

# T4: `each_with_index` block doing direct `f[:k] = v`
arr4 = [{x: 1}, {x: 3}]
arr4.each_with_index { |f, i| f[:x] = i * 10 }
puts arr4[0][:x].to_s
puts arr4[1][:x].to_s
