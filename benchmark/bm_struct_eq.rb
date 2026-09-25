# struct-eq benchmark: equality, hash and to_a of Structs, as the
# compiler compares its nodes and walks their children
Pair = Struct.new(:left, :right, :line)

a = Pair.new(:a, 1, 3)
b = Pair.new(:a, 1, 3)
c = Pair.new(:a, 2, 3)
seen = {}
n = 0
i = 0
while i < 1000000
  n += 1 if a == b
  n += 1 if a == c
  n += 1 if a.eql?(b)
  n += a.to_a.size
  seen[a] = i
  i += 1
end
puts n
puts seen.size
puts "done"
