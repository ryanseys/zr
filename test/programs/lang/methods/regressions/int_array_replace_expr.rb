# `Array#replace` in *expression* position on an int_array.
# The stmt-form arm has long supported this; the expr-form was
# missing — unresolved-call warning + literal `0` emitted.
# Surfaced via optcarrot's `def load_battery; ...; @wrk.replace(sav.bytes); end`,
# where the call sits at the tail of the method (its value is
# the implicit return).

a = [1, 2, 3]
b = [10, 20, 30, 40]

# Expression position: assigned. Should yield the (mutated) `a`.
c = a.replace(b)

# `a` mutated in place
puts a[0]
puts a[1]
puts a[2]
puts a[3]
puts a.length

# `c` is the same array (replace returns the receiver)
puts c[0]
puts c.length
