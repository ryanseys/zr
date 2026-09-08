# `Ractor.new` is decided by the SITE: the block is the ractor's body and
# is moved in whole, so it never reaches the send road. The isolation
# verdict rides on the Proc, which is why a captured name refuses here and
# not where the proc was written.

r = Ractor.new(20) { |n| n + 1 }
p r.value

named = Ractor.new(name: "worker") { 7 }
p named.name
p named.value

sink = Ractor.new do
  a = Ractor.receive
  b = Ractor.receive
  a * b
end
sink.send(6)
sink.send(7)
p sink.value

doubler = ->(x) { x + x }
p Ractor.new(4, &doubler).value

def spawn(&blk) = Ractor.new(10, &blk)
p spawn { |x| x + 5 }.value

outer = 1
bad = proc { outer + 1 }
begin
  Ractor.new(&bad)
rescue ArgumentError => e
  puts e.message
end

begin
  Ractor.new(&nil)
rescue ArgumentError => e
  puts e.message
end
__END__
21
"worker"
7
42
8
15
can not isolate a Proc because it accesses outer variables (outer).
must be called with a block
#@ stderr
ze0/ractor.rb:6: warning: Ractor API is experimental and may change in future versions of Ruby.
