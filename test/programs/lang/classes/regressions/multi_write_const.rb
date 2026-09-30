# Multi-write to constants — `A, B, C = expr` — sets each constant.
#
# Two RHS shapes are exercised: an Array literal and a constant that
# holds an Integer Array.

class T_multi_write_const_C
  N1, N2, N3 = [10, 20, 30]
end

puts T_multi_write_const_C::N1
puts T_multi_write_const_C::N2
puts T_multi_write_const_C::N3

class T_multi_write_const_D
  ARR = [100, 200, 300, 400]
  M1, M2, M3, M4 = ARR
end

puts T_multi_write_const_D::M1
puts T_multi_write_const_D::M2
puts T_multi_write_const_D::M3
puts T_multi_write_const_D::M4

# RHS with a block — the block param is a local of the block, and
# each constant gets one mapped value.
P, Q = [1, 2].map { |n| n * 10 }
puts P
puts Q
