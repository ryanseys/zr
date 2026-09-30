# Array#sum starts from its init argument, with or without a block:
#   [1,2,3].sum(10)             # => 16
#   [].sum(7)                   # => 7
#   [1,2,3].sum(10) { |x| x*2 } # => 22

# Integer array, no block
puts [1, 2, 3].sum(10)            # 16
puts [1, 2, 3].sum                # 6   (no init)
puts [].sum(7)                    # 7   (empty + init survives)
puts [].sum                       # 0   (empty default still 0)
puts [1, 2].sum(-5)               # -2  (negative init)

# Integer array, with block
puts [1, 2, 3].sum(10) { |x| x * 2 }   # 22
puts [1, 2, 3].sum { |x| x * 2 }       # 12  (block, no init)
puts [].sum(7) { |x| x * 2 }           # 7   (empty + init w/ block)

# Float array, no block
puts [1.5, 2.5].sum(0.5)          # 4.5
puts [1.5, 2.5].sum               # 4.0 (no init)
puts [1.5, 2.5].sum(1)            # 5.0 (Integer init becomes a Float sum)
puts [1.5, 2.5].sum(-0.5)         # 3.5 (negative float init)

# The init comes from an element of a mixed array, so its type is not
# known before run time.
poly_arr = [10, "x"]
init_p = poly_arr[0]
puts [1, 2].sum(init_p)           # 13 (Integer init)

fpoly_arr = [1.5, "x"]
finit_p = fpoly_arr[0]
puts [1.0, 2.0].sum(finit_p)      # 4.5 (Float init)

# An Integer init for a Float array converts to a Float value.
# It does not reuse the Integer's bits as a Float.
ipoly_for_float = [1, "x"][0]
puts [1.0, 2.0].sum(ipoly_for_float)   # 4.0 (Integer init, Float array)

# Float array, with block and Float init: the 0.5 seed and the Float
# block results are not truncated. The block parameters have their
# own names (`fx` / `fy`), not the `|x|` of the Integer blocks above.
puts [1.5, 2.5].sum(0.5) { |fx| fx }      # 4.5
puts [1.0, 2.0].sum { |fy| fy * 1.5 }     # 4.5

puts "done"
