# Ruby distinguishes "the caller wrote keywords" from "the caller passed a
# Hash". Every callee that asks the question must get the right answer,
# no matter which call shape reaches it.
#
# A `**h` double-splat and `send` are the two call shapes to check. A
# LITERAL keyword at a statically-resolved site keeps the distinction
# and already answers correctly, which is the control in each pair
# below.
#
# `**nil` is the sharpest reader of the flag, since refusing keywords is
# its whole purpose.
#
# An EMPTY `**{}` passes no keywords at all, so it must stay silent -- that is
# the line separating this from a shape-only test.

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue ArgumentError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

def nokw(a, **nil) = a
def nokw_splat(*a, **nil) = a

# The literal form keeps the flag -- already correct.
show("literal kw") { nokw(1, b: 2) }
show("literal, rest") { nokw_splat(1, b: 2) }

# A `**h` splat loses it.
show("splat kw") { h = { b: 2 }; nokw(1, **h) }
show("splat kw, rest") { h = { b: 2 }; nokw_splat(1, **h) }

# `send` loses it.
show("send kw") { send(:nokw, 1, b: 2) }

# A real positional Hash must keep working, and an empty splat passes nothing.
show("positional hash") { nokw({ b: 2 }) }
show("rest positional hash") { nokw_splat(1, { b: 2 }) }
show("empty splat") { h = {}; nokw(1, **h) }
