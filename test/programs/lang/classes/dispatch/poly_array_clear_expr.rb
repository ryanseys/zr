# `Array#clear` in *expression* position on a mixed array.
# `c = a.clear` gives `c` the cleared array itself.
#
# optcarrot has the `@sp_visible ||= @sp_map.clear` shape. Here
# the `||=` form gets a typed initializer first.

a = [1, "two", :three, [4, 5]]
b = a.clear

puts a.length    # 0
puts b.length    # 0 (b is a, just emptied — same array, just mutated)

# Subsequent push refills from index 0.
a.push(99)
puts a.length    # 1
