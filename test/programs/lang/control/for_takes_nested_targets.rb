# ruby 4.1's `for` takes nested targets, as a multiple assignment does:
# each yielded value destructures into them, and the names stay in the
# enclosing scope after the loop.
for (a, b), c in [[[1, 2], 3], [[4, 5], 6]]
  p [a, b, c]
end
p [a, b, c]

for x, (y, (z, *w)) in [[1, [2, [3, 4, 5]]], [6, [7, 8]]]
  p [x, y, z, w]
end

for (i, *j), k in [[[1, 2, 3], 4], [5, 6]]
  p [i, j, k]
end

for (m, n) in [[1, 2], [3, 4]]
  p [m, n]
end

def yielder
  yield [1, 2], 3
  yield [4, 5]
end

for (u, v), t in to_enum(:yielder)
  p [u, v, t]
end

for (e1, e2), e3 in [[nil, 1], [[1], 2], [[1, 2, 3], 4], [1, 2]]
  p [e1, e2, e3]
end
p(for (aa, bb), cc in [[[1, 2], 3]]; end)
