# reverse! swaps the elements where they are and answers the receiver;
# reverse, reverse_each and a subclass read a plain reversed copy.
a = [1, 2, 3, 4, 5]
p a.reverse!.equal?(a), a, a.reverse!, [].reverse!, [1].reverse!, [1, 2].reverse!
b = a.reverse
p b, b.class, a, a.reverse_each.to_a, a.reverse.equal?(a)
class Stack < Array; end
s = Stack.new([3, 1, 2])
p s.reverse.class, s.reverse!.class, s
f = [1, 2].freeze
p (f.reverse! rescue $!.class), f.reverse
q = (1..10_000).to_a
q.reverse!
p q.first(3), q.last(3), q.reverse.first(3), [].method(:reverse!).arity, [].method(:reverse!).source_location

