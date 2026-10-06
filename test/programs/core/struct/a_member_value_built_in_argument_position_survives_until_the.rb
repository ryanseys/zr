# A Struct member value built in argument position must survive until the
# constructor stores it. A sibling member expression can cause a collection
# while the call's arguments are still being evaluated. Members are placed on
# both sides of the allocating one, so the order of evaluation does not matter.
Inner = Struct.new(:n)
Tri = Struct.new(:head, :bulk, :tail)

def churn(i)
  ls = []
  60.times { |j| ls.push("line #{i} #{j} ......................") }
  GC.start
  ls.join("\n")
end

built = []
40.times { |i| built.push(Tri.new(Inner.new(i), churn(i), "t#{i}")) }
bad_head = 0
bad_tail = 0
built.each_with_index do |o, i|
  bad_head += 1 if o.head.n != i
  bad_tail += 1 if o.tail != "t#{i}"
end
p bad_head
p bad_tail

# The same for a Data instance, which shares the constructor emitter.
Pair = Data.define(:name, :bulk)
pairs = []
40.times { |i| pairs.push(Pair.new("n#{i}", churn(i))) }
p pairs.each_with_index.count { |d, i| d.name != "n#{i}" }
