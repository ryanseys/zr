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


# Reads a[i]; if truthy, sets a[i] = v. Stick to non-zero values
# so the C-truthy semantic agrees with Ruby's truthy semantic.
xs_aw = [1, 2, 3, 4, 5]
xs_aw[0] &&= 10              # truthy -> fires
xs_aw[2] &&= 30              # truthy -> fires
xs_aw[4] &&= xs_aw[4] * 100  # truthy -> fires; recv/idx evaluated once
puts xs_aw[0]                # 10
puts xs_aw[1]                # 2
puts xs_aw[2]                # 30
puts xs_aw[3]                # 4
puts xs_aw[4]                # 500

counts_aw = {"alice" => 30, "bob" => 25}
counts_aw["alice"] &&= 31    # truthy -> fires
counts_aw["carol"] &&= 50    # unset (returns 0) -> doesn't fire
puts counts_aw["alice"]      # 31
puts counts_aw["bob"]        # 25
puts counts_aw.length        # 2 (carol not added)
