# Integer receiver + an argument that can be of mixed classes, in
# arithmetic. Common case: `addr + arr[i][j]`, where `arr` holds a
# user object and an Integer Array. `[]` on each returns an Integer,
# so the arithmetic gives an Integer.

# Class that defines `[]` returning an Integer, stored alongside an
# Integer Array.
class T_poly_int_arith_auto_unify_Lookup
  def [](i); i * 10 + 1; end
end

arr = [T_poly_int_arith_auto_unify_Lookup.new, [100, 200, 300]]

# arr[i] is a T_poly_int_arith_auto_unify_Lookup or an Integer Array, then `[j]` is called on it —
# each one returns an Integer.
addr = 7
puts(addr + arr[1][0])  # 7 + 100 = 107
puts(addr - arr[0][2])  # 7 - 21  = -14
puts(addr * arr[1][1])  # 7 * 200 = 1400
puts(arr[1][2] / 3)     # 300 / 3 = 100
