# MultiTargetNode -- nested LHS in destructuring multi-assign.
#
#   a, (b, c), d = 1, [2, 3], 4
#
# Each parenthesized group on the LHS is a MultiTargetNode that
# recursively unpacks its slot of the RHS. Here each inner-array RHS
# slot holds one element type (Integer, String or Float). This test
# does not cover two-level nesting where intermediate slots are
# heterogeneous.

a, (b, c), d = 1, [2, 3], 4
puts a    # 1
puts b    # 2
puts c    # 3
puts d    # 4

# String-typed inner array
x, (s, t), y = 10, ["hello", "world"], 20
puts x    # 10
puts s    # hello
puts t    # world
puts y    # 20
