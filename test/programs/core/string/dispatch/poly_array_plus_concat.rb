# `Array#+` on an array value of unknown type concatenates. When a record
# field's only initializer is an empty `[]`, its element type is unresolvable,
# so it is stored as a boxed value and `+` goes through the dynamic `+`
# dispatcher. That dispatcher concatenates when both operands are arrays.
M = Data.define(:xs)

m = M.new(xs: [])
m2 = m.with(xs: m.xs + ["a", "b"])
p m2.xs
p m2.xs.size

n = M.new(xs: [])
p (n.xs + [1, 2]).size          # poly array + int array
p (n.xs + [[1], [2]]).length    # poly array + nested array
