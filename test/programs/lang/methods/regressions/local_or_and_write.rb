# `LocalVariableOrWriteNode` (`a ||= b`) and
# `LocalVariableAndWriteNode` (`a &&= b`) parse as their own
# AST nodes — distinct from `LocalVariableOperatorWriteNode`
# (which carries `+`, `-`, `*`, etc. via a binary_operator field).
# Without dedicated parser cases the prism nodes were dropped on
# the floor, so `a ||= b` produced no C output.

# (1) Statement-form ||=
a = nil
a ||= 10
puts a       # 10
a ||= 99     # already truthy → no-op
puts a       # 10

# (2) Statement-form &&=
b = 5
b &&= b + 1
puts b       # 6
c = nil
c &&= 99     # nil → no-op
puts c.nil? ? "nil" : c.to_s   # nil

# (3) Expression-form ||=
x = nil
y = (x ||= 7)
puts x       # 7
puts y       # 7

# (4) Expression-form &&=
p = 3
q = (p &&= p * 2)
puts p       # 6
puts q       # 6
