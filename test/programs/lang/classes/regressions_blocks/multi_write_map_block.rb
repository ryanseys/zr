# `A, B = arr.map { block }` is destructuring assignment where
# each LHS target receives one element of the mapped array.
# Here the block returns an Integer Array, so each constant holds an
# Integer Array.

class T_multi_write_map_block_C
  # Outer map produces an Array of Arrays (each element is an Integer
  # Array from `to_a`).
  P, Q = [3, 5].map { |n| (0...n).to_a }
end

# P and Q are Arrays, so `.length` and `[]` work on them.
puts T_multi_write_map_block_C::P.length   # 3
puts T_multi_write_map_block_C::P[0]       # 0
puts T_multi_write_map_block_C::P[1]       # 1
puts T_multi_write_map_block_C::P[2]       # 2
puts T_multi_write_map_block_C::Q.length   # 5
puts T_multi_write_map_block_C::Q[3]       # 3
puts T_multi_write_map_block_C::Q[4]       # 4
