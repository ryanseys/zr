# Splat destructure with a RHS array of mixed element types. Each target
# gets its element, and the splat target gets an Array of the rest.

def heterogeneous
  ["alpha", 1, "beta", 2.5, "gamma"]
end

# Trailing splat — splat target is an Array holding the tail.
a, b, *rest = heterogeneous
puts a              # alpha
puts rest.length    # 3

# Leading splat — splat target holds the head, then two scalar tails.
*head, y, z = heterogeneous
puts head.length    # 3
puts z              # gamma
puts y              # 2.5  — a Float element from the mixed RHS

# Middle splat — targets on both sides of the splat.
p, *mid, q = heterogeneous
puts mid.length     # 3
puts p              # alpha
puts q              # gamma
