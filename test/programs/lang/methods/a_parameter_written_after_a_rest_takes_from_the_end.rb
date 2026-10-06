# Positional parameter shapes: parenthesized destructuring, the auto-splat
# rule, post-parameter distribution, and the trailing-comma implicit rest.

def one(x) = yield x

# --- Post parameters --------------------------------------------------------
# Post params fill left-to-right from whatever the lead/rest left behind, and
# nil-pad when there isn't enough to go around.
one([1, 2]) { |a, *b, c, d| p [a, b, c, d] }
one([1, 2, 3, 4, 5]) { |a, *b, c| p [a, b, c] }
one([1, 2]) { |a, b = 5, c = 6, d, e| p [a, b, c, d, e] }
one([1, 2, 3, 4, 5]) { |a, b = 5, c = 6, d, e| p [a, b, c, d, e] }

# The same clamping in a multi-assignment.
w, *x, y, z = [1, 2]
p [w, x, y, z]

