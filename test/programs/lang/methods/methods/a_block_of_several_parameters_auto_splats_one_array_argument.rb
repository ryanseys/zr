# Positional parameter shapes: parenthesized destructuring, the auto-splat
# rule, post-parameter distribution, and the trailing-comma implicit rest.

def one(x) = yield x

# --- Auto-splat -------------------------------------------------------------
# A lone Array argument spreads across a block's positional params -- but a
# block taking exactly one plain param receives it WHOLE (the `each { |pair| }`
# idiom), and so does a lone optional.
one([1, 2]) { |a| p a }
one([1, 2]) { |a = 9| p a }
one([1, 2]) { |*a| p a }
one([1, 2]) { |a, **k| p a }

# Two or more positional slots spread it.
one([1, 2]) { |a, b| p [a, b] }
one([1, 2]) { |a, *b| p [a, b] }
one([1, 2]) { |*a, b| p [a, b] }

# More than one OPTIONAL spreads it, even with no required param at all --
# while a single optional plus a rest does not.
one([1, 2]) { |a = 5, b = 4| p [a, b] }
one([1, 2]) { |a = 5, *b| p [a, b] }

# A lambda is strict and never auto-splats.
p(->(a) { a }.call([1, 2]))

