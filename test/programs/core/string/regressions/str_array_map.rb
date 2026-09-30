# Array#map on a String array. `tt = foo.map { |s| ... }` gives the
# mapped Array, and a later iteration over it works.

# String -> string map
foo = ["a", "b", "c"]
tt = foo.map { |s| s.upcase }
tt.each { |t| puts t }   # A B C

# String -> int map: codepoint length, returning an Integer array
sizes = foo.map { |s| s.length }
puts sizes.length         # 3
puts sizes[0]             # 1
puts sizes[1]             # 1
puts sizes[2]             # 1

# Original receiver is unchanged
puts foo[0]               # a
puts foo[1]               # b
puts foo[2]               # c

# .map { ... }.each { ... } chain (the issue's pattern)
words = ["alpha", "beta", "gamma"]
words.map { |w| w.upcase }.each { |w| puts w }   # ALPHA BETA GAMMA

# Empty input
empty = "".split(",")
e2 = empty.map { |s| s.upcase }
puts e2.length            # 0

# Block parameter is block-local: reusing the same name as an outer
# differently-typed local must not leak (3.times do |i| ... end, then
# foo.map {|i| ...} with a String `i`).
rs = []
3.times do |i|
  rs << "row#{i}"
end
out = rs.map { |i| i.upcase }
out.each { |line| puts line }   # ROW0 ROW1 ROW2
