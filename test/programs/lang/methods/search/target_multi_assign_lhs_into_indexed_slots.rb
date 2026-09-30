# Indexed-slot compound writes — `a[i] OP= v`, `a[i] &&= v`,
# `a[i] ||= v`, `a[i], b[j] = ...`. Was four tests; merged here.
# The op_assign section's `class Vec` is unique; locals reused
# across the originals (`xs`, `counts`, etc.) get per-section
# prefixes so the merged script's type inference doesn't unify
# them or carry hash content across sections.

class Vec
  attr_accessor :data
  def initialize(n)
    @data = Array.new(n, 0.5)
  end
end


# `a[0], b[1] = 1, 2` -- each LHS slot is an IndexTargetNode.
xs_t = [10, 20, 30]
ys_t = [100, 200, 300]
xs_t[0], ys_t[2] = 1, 999
puts xs_t[0]                 # 1
puts xs_t[1]                 # 20
puts ys_t[2]                 # 999

# Same-array two-slot swap.
zs_t = [1, 2, 3, 4, 5]
zs_t[0], zs_t[4] = zs_t[4], zs_t[0]
puts zs_t[0]                 # 5
puts zs_t[4]                 # 1

# Hash slot mixed with array slot in one multi-assign.
counts_t = {"a" => 0, "b" => 0}
arr_t = [0, 0, 0]
counts_t["a"], arr_t[1] = 42, 99
puts counts_t["a"]           # 42
puts arr_t[1]                # 99
