# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# Two rings: `a << a`, and `b << [2, b]` whose inner array is the third array. The nested one is the row that proves the guard is a stack.
# At exit: cycle leak: 3 objects (Array x3)
# `Array#join` on a self-referential array raises ArgumentError
# ("recursive array join"), and the process goes on. The nested join
# re-enters the receiver while the outer join still uses it.

a = [1]
a << a
begin
  a.join(",")
rescue ArgumentError => e
  puts e.message
end

# Nested one level deeper, so the guard has to be a STACK and not a flag
# on the receiver.
b = [1]
b << [2, b]
begin
  b.join(",")
rescue ArgumentError => e
  puts e.message
end

# A sibling is not a cycle: the same array twice is legal, and stays legal.
# This is what a monotonic visited-set would break.
c = [1, 2]
p [c, c].join(",")
p [c, [c, c]].join("-")

# Every ordinary join still works, including the nested and separatorless
# forms.
p [1, [2, [3, 4]], 5].join("-")
p [1, [2]].join
p [].join(",")
p [[], [[]]].join(",")
