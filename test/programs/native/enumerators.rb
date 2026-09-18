# External iteration runs on a fiber.
p [1, 2].each.inspect, [1, 2].each_slice(2).inspect, [1, 2].map.inspect, [1, 2].each.size, [1, 2].each_slice(2).size, (1..3).each.size, 3.times.size
p [1, 2].each_with_index.to_a, [1, 2].each.with_index(1).to_a, [1, 2].map.with_index { |x, i| x * i }, [1, 2].each_with_object([]).to_a, { a: 1 }.each.to_a, { a: 1 }.map.with_index.to_a, %w[a b].each_with_index.map { |s, i| s * (i + 1) }
e = [1, 2].each
p e.next, e.peek, e.next
begin
  e.next
rescue StopIteration => x
  p x.message
end
e.rewind
p e.next
p [1, 2, 3].each_slice(2).with_index.to_a, [4, 5].each.with_index(10).map { |x, i| [x, i] }, [1, 2].select.with_index { |x, i| i == 0 }
p Enumerator.new { |y| y.yield 1, 2; y << 3 }.to_a, Enumerator.new { |y| y << 1 }.next, [1, 2].to_enum(:each_slice, 1).to_a, [3].enum_for.to_a
begin
  Enumerator.new
rescue ArgumentError => x
  p x.message
end
p [1, 2].each_entry.to_a, [[1, 2]].each_entry.to_a, [1, 2].reverse_each.to_a, [1, 2, 3].each_cons(2).to_a, [1, 2, 3].each_index.to_a, 3.times.to_a, 1.upto(3).to_a, 3.downto(1).to_a, [1, 2].find_index.to_a
p [1, 2].each_slice(2).size, [1, 2, 3].each_cons(2).size, %w[x].each_with_index.size, [1].cycle(2).size, (1..4).each_slice(3).size
p [1, 2].map.class, [1, 2].select.class, [1, 2].reject.class, [1, 2].each_with_index.class, [1, 2].group_by.class, [1, 2].sort_by.class, [1, 2].flat_map.class
gen = Enumerator.new do |y|
  y << :a
  y << :b
end
p gen.map(&:to_s), gen.first, gen.first(1), gen.include?(:b), gen.count, gen.to_a, gen.next, gen.next
p [1, 2, 3].each_with_index.select { |x, i| i > 0 }, [1, 2, 3].each.with_object(:memo).to_a, [[1, 2], [3, 4]].each_with_index.map { |(a, b), i| a + b + i }
p({ a: 1, b: 2 }.each_with_index.map { |(k, v), i| [k, v, i] })
p [1, 2, 3].select.with_index { |x, i| i.even? }
e = [1, 2].each
p loop { e.next }
e2 = (1..3).each
p loop { e2.next }
p loop { break 5 }
p [3, 4].each_with_index.next
e3 = [[1, 2], 3].each
p e3.next, e3.peek, e3.next
begin
  e3.next
rescue StopIteration => x
  p x.message, x.result, x.instance_variables
end
p 3.loop rescue p $!
def m = loop
p m.class
i = 0
loop do
  i += 1
  break if i > 3
end
p i
def n
  loop { return 9 }
end
p n
begin
  loop { raise "in loop" }
rescue => err
  puts err.backtrace
end
