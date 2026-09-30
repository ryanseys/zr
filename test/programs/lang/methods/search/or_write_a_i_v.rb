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


# Reads a[i]; if falsy, sets a[i] = v. Receiver and index are
# evaluated exactly once even though the source has them on both
# sides of the implicit `a[i] = a[i] || v`.
counts_or = {"alice" => 0, "bob" => 5}
counts_or["carol"] ||= 10    # never set -> fires
counts_or["bob"]   ||= 99    # 5 truthy -> no-op
puts counts_or["alice"]      # 0
puts counts_or["bob"]        # 5
puts counts_or["carol"]      # 10
