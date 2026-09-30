# `arr.map { ... }.join(sep)` on a receiver whose type is known only
# at run time (e.g. a parameter with a `= nil` default). The map
# works for each kind of Array, and join gives the joined String.

def joined(arr = nil)
  return "(empty)" if arr.nil?
  arr.map { |x| "v=#{x}" }.join(",")
end

puts joined(["a", "b"])
puts joined(["x"])
puts joined([])
puts joined(nil)

# Heterogeneous (poly-array) elements via the same poly param.
def joined_int(arr = nil)
  return "(none)" if arr.nil?
  arr.map { |x| "n=#{x}" }.join(";")
end

puts joined_int([1, 2, 3])
