# merge on a hash with Symbol keys and mixed values, with a
# positional argument that has Symbol keys and Integer values.
# The result holds the values of both.

def f
  h = { a: "x", b: 1 }
  other = { c: 2 }
  h.merge(other)
end

m = f
puts m.length
puts m.has_key?(:a)
puts m.has_key?(:b)
puts m.has_key?(:c)
