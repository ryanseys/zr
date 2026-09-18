# External iteration runs on a fiber.
fib = Enumerator.new do |y|
  a, b = 0, 1
  loop do
    y << a
    a, b = b, a + b
  end
end
p fib.next, fib.next, fib.next, fib.peek, fib.next, fib.take(8), fib.next
ticks = Enumerator.new { |y| i = 0; loop { y.yield(i += 1) } }
p 5.times.map { ticks.next }
ticks.rewind
p ticks.next
pairs = Enumerator.new { |y| y.yield 1, 2; y.yield; y.yield 3; y << [4, 5]; :fin }
p pairs.next_values, pairs.next_values, pairs.peek_values, pairs.next, pairs.next
begin
  pairs.next
rescue StopIteration => e
  p e.message, e.result, e.cause
  begin
    pairs.next
  rescue StopIteration => f
    p f.message, f.result, f.cause.equal?(e), f.equal?(e)
  end
end
p pairs.next_values rescue p $!.class
pairs.rewind
p pairs.next
ans = [1, 2, 3].each
p ans.next, ans.next, ans.next
begin
  ans.next
rescue StopIteration => e
  p e.result
end
boom = Enumerator.new { |y| y << 1; raise ArgumentError, "inside" }
p boom.next
begin
  boom.next
rescue ArgumentError => e
  p e.message
end
p boom.next
h = { a: 1, b: 2 }.each
p h.next, h.peek, h.next
p h.next rescue p $!.message
words = %w[x y z].each_with_index
p words.next, words.next
ex = [10, 20].each
p ex.next
p ex.peek, ex.peek, ex.next
p (ex.next rescue :done)
def generator
  return to_enum(:generator) unless block_given?

  yield 1
  yield 2, 3
  :answer
end
g = generator
p g.next, g.next
begin
  g.next
rescue StopIteration => e
  p e.result
end
zipped = [1, 2, 3].each
other = %w[a b c].each
p 3.times.map { [zipped.next, other.next] }
gc = Enumerator.new { |y| 20.times { |i| GC.start; y << i.to_s * 3 } }
p 20.times.map { gc.next }.last
inner = Enumerator.new { |y| outer = [1, 2].each; y << outer.next; y << outer.next; y << (outer.next rescue :end) }
p inner.next, inner.next, inner.next
inf = Enumerator.new { |y| i = 0; loop { y << (i += 1) } }.lazy
p [1, 2].lazy.zip(inf).to_a, [1, 2].lazy.zip(inf, [7]).first(1), inf.zip(inf.map { |x| -x }).first(2)
e = [1, 2, 3].lazy.map { |x| x * 2 }
p e.next, e.next, e.peek, e.next
begin
  e.next
rescue StopIteration => x
  p x.message
end
p e.rewind.next
p [4, 5].lazy.take(1).eager.next
