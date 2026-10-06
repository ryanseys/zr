# Expression shapes: multi-value return/break/next, parenthesized
# statement sequences, the fuller interpolation forms, and top-level
# instance variables.

# --- return / break / next with several values ------------------------------
# More than one value builds an implicit array -- the same array the
# equivalent literal would, splats included.
def pair
  return 1, 2
end
p pair

def triple
  return 1, 2, 3
end
p triple

def with_splat(a)
  return 1, *a
end
p with_splat([2, 3])

# A SINGLE splat is an array too -- `return *a` where a == [1] is [1], not 1.
def splat_only(a)
  return *a
end
p splat_only([1, 2])
p splat_only([1])
p splat_only([])

# A bare `return` is still nil.
def nothing
  return
end
p nothing

# break/next take the same shape.
p([1].each { break 1, 2 })
p([[1, 2]].map { |a, b| next a, b })

