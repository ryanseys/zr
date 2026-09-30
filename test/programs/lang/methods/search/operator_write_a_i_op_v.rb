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


# Float / Int / hash receivers, both directly and through an
# object field. IndexOperatorWriteNode is distinct from a `.[]=`
# call; without the dedicated codegen the update is dropped.

vop1 = Vec.new(4)
vop1.data[0] += 1.5
vop1.data[1] -= 0.5
vop1.data[2] *= 4.5
vop1.data[3] /= 0.5
puts vop1.data[0]   # 2.0
puts vop1.data[1]   # 0.0
puts vop1.data[2]   # 2.25
puts vop1.data[3]   # 1.0

ints_op = Array.new(3, 10)
ints_op[0] += 5
ints_op[1] -= 3
ints_op[2] *= 2
puts ints_op[0]     # 15
puts ints_op[1]     # 7
puts ints_op[2]     # 20

counts_op = {"a" => 1, "b" => 2}
counts_op["a"] += 10
counts_op["b"] += 20
puts counts_op["a"] # 11
puts counts_op["b"] # 22

# Same pattern through a method call on an object: `obj.attr[i] += x`.
vop2 = Vec.new(3)
iop = 0
while iop < 3
  vop2.data[iop] += 0.25
  iop += 1
end
puts vop2.data[0]   # 0.75
puts vop2.data[1]   # 0.75
puts vop2.data[2]   # 0.75
