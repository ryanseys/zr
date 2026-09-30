# Positional parameter shapes: parenthesized destructuring, the auto-splat
# rule, post-parameter distribution, and the trailing-comma implicit rest.

def one(x) = yield x

# --- Parenthesized destructuring --------------------------------------------
# A single fully-parenthesized param splits the element it receives.
[[1, 2], [3, 4]].each { |(a, b)| p [a, b] }

# Mixed with plain params, at any position.
[[1, [2, 3], 4]].each { |a, (b, c), d| p [a, b, c, d] }
[[[1, 2], 3]].each { |(a, b), c| p [a, b, c] }

# Nested arbitrarily deep.
[[1, [2, [3, 4]]]].each { |a, (b, (c, d))| p [a, b, c, d] }

# A named splat inside the destructure collects the tail; an anonymous one
# consumes its slot and discards it.
[[1, [2, 3, 4]]].each { |a, (b, *r)| p [a, b, r] }
[[1, 2, 3]].each { |a, (*), b| p [a, b] }

# Destructuring works on METHOD params too, not just blocks.
def pair((a, b)) = "#{a}-#{b}"
puts pair([1, 2])

def nested((a, (b, c))) = [a, b, c]
p nested([1, [2, 3]])

# The destructured names are ordinary locals: an escaping block can capture
# them, and reassigning one inside the block is visible outside.
def capture((a, b))
  bump = -> { a += 10 }
  bump.call
  [a, b]
end
p capture([1, 2])

