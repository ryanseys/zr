# Sibling case to "str poly hash dup widen": here the source Hash has
# Integer values. Reads from the copy give the original Integers.

class Counter
  attr_reader :counts
  def initialize(h); @counts = h; end
end

c = Counter.new({ "a" => 1, "b" => 2 })
merged = c.counts.dup
merged["x"] = "label"   # str value forces analyzer-side widening
puts merged["a"]
puts merged["b"]
puts merged["x"]
