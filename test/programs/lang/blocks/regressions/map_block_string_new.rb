# `.map { String.new }` answers an Array of mutable Strings, as the
# literal `[String.new]` does.

xs = [1, 2, 3]

# Block returns String.new directly.
result = xs.map { |x| String.new }
puts result.length

# Block returns a local that holds a mutable String.
result2 = xs.map { |x| s = String.new; s << "v"; s }
puts result2.length
