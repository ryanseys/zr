# pop, shift and unshift are kernel entries with the count of `pop(n)`
# and `shift(n)` read there, and first and last stay ruby's own Ruby:
# the same answers, errors in the same order, plain Arrays from a
# subclass, and a queue that shifts and unshifts in place.
a = [1, 2, 3, 4, 5]
p a.first, a.last, a.first(2), a.last(2), a.first(0), a.last(9), a.first(2.9)
p a.pop, a.pop(2), a, a.shift, a.shift(3), a, a.shift, a.pop, a.shift(2), a.pop(1)
b = [3, 4]
p b.unshift(1, 2), b.unshift, b.prepend(0), b.shift(2), b.unshift(:x), b
p (b.first(-1) rescue $!.class), (b.pop(-1) rescue $!.message), (b.shift("x") rescue $!.class), (b.first(1, 2) rescue $!.message)
f = [1].freeze
p (f.pop rescue $!.class), (f.pop(-1) rescue $!.class), (f.shift(0) rescue $!.class), (f.unshift rescue $!.class), f.first(1), f.last(0)
class Stack < Array; end
s = Stack.new([1, 2, 3])
p s.first(2).class, s.last(2).class, s.pop(1).class, s.shift(1).class, s.class
q = []
20_000.times { |i| q.push(i); q.unshift(-i) }
sum = 0
sum += q.shift while q.size > 10
p sum, q.size, q.first(3), q.last(3)
p [].method(:pop).arity, [].method(:first).parameters, [].method(:shift).owner, [].method(:unshift).source_location
p %w[a b c].method(:first).unbind.bind_call([7, 8], 1), [[1, 2]].first.first(1)

