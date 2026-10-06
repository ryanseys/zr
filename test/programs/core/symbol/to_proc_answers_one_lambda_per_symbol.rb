# `Symbol#to_proc` and `&:name` answer the same lambda for a symbol
# every time, as ruby keeps one per symbol; it is a lambda, not
# frozen, and it keeps what a program puts on it.
a = :upcase.to_proc
b = :upcase.to_proc
p a.equal?(b), a.lambda?, a.frozen?, a.arity, a.call("x")
a.instance_variable_set(:@tag, 1)
p :upcase.to_proc.instance_variable_get(:@tag)
pr = nil
2.times { |i| q = ->(&blk) { blk }.call(&:downcase); p pr.equal?(q) if pr; pr = q }
GC.start
p pr.equal?(:downcase.to_proc), pr.call("ABC")
dyn = "dyn#{1 + 1}".to_sym
p dyn.to_proc.equal?(dyn.to_proc), :dyn2.to_proc.equal?(dyn.to_proc)
p %w[a b].map(&:upcase), [1, 2].map(&:to_s), [[1, 2]].map(&:first)
p :+.to_proc.call(1, 2), :size.to_proc.parameters, :size.to_proc.source_location
p :"with space".to_proc.call(Struct.new(:"with space").new(3))


