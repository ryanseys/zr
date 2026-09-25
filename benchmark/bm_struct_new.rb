# struct-new benchmark: a Struct made by position, as the compiler makes
# its HIR nodes, some with fewer values than members
Node = Struct.new(:recv, :name, :args, :line)

def make(i)
  Node.new(nil, :call, i, 1)
end

sum = 0
i = 0
while i < 1000000
  sum += make(i).args
  sum += Node.new(nil, :x).line.to_i
  i += 1
end
puts sum
puts "done"
