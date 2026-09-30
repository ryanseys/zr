# Positional parameter shapes: parenthesized destructuring, the auto-splat
# rule, post-parameter distribution, and the trailing-comma implicit rest.

def one(x) = yield x

# --- Trailing comma ---------------------------------------------------------
# `|a, |` means "more than one param", which turns on auto-splat, then
# discards everything past `a`.
one([1, 2]) { |a,| p a }

