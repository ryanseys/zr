# Nested multiple-assignment from a poly-typed RHS (an Integer|Array union, not
# a statically-typed array), which destructures at run time.
def maybe(f)
  return 0 unless f
  [[1, [2, 3]], 4]
end
x = maybe(true)
(a, (b, c)), d = x
p [a, b, c, d]
