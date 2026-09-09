l = [1, 2, 3].lazy
p l, l.class, l.size, l.to_a, l.force, l.first, l.first(2), l.lazy.equal?(l), l.eager, l.eager.class
p l.map { |x| x * 2 }, l.map { |x| x * 2 }.to_a, l.select(&:odd?).to_a, l.reject(&:odd?).force, l.filter_map { |x| x * 10 if x > 1 }.to_a
p l.take(2), l.take(2).to_a, l.take(0).to_a, l.take(5).to_a, l.drop(1).to_a, l.drop(5).to_a, l.take_while { |x| x < 3 }.to_a, l.drop_while { |x| x < 2 }.to_a
p l.map { |x| x * 2 }.size, l.select(&:odd?).size, l.take(2).size, l.take(9).size, l.drop(1).size, l.drop(9).size, l.with_index.size, l.zip([1]).size, l.take_while { true }.size
nat = (1..Float::INFINITY).lazy rescue nil
inf = Enumerator.new { |y| i = 0; loop { y << (i += 1) } }.lazy
p inf.map { |x| x * x }.select(&:even?).first(3), inf.take(3).to_a, inf.take_while { |x| x < 4 }.to_a, inf.drop(2).first(2), inf.drop_while { |x| x < 5 }.first(2)
p inf.map { |x| x * 2 }.take(2).map { |x| x + 1 }.to_a, inf.take(4).select(&:even?).force, inf.flat_map { |x| [x, -x] }.first(4), inf.filter_map { |x| x if x % 3 == 0 }.first(2)
p inf.each_slice(2).first(2), inf.each_cons(2).first(2), inf.each_with_index.first(2), inf.with_index(10).first(2), inf.each_with_object(:o).first(1), inf.uniq { |x| x % 3 }.first(3)
p l.map { |x| x * 3 }.take(2), l.take(2).map { |x| x }, l.each_slice(2), l.with_index(1), l.with_index, l.zip([1]), l.uniq, l.compact, l.grep(1..3), l.each_with_index, l.filter_map { |x| x }, l.each_with_object(1).size, l.each_with_object(1).each {}
p [nil, 1, nil, 2].lazy.compact.to_a, [1, 1, 2].lazy.uniq.to_a, [1, "a", :b].lazy.grep(String).to_a, [1, "a", :b].lazy.grep(String, &:upcase).to_a, [1, "a", :b].lazy.grep_v(String).to_a, [1, 2, 3].lazy.grep(2..3) { |x| x * 5 }.to_a
p [1, 2, 3].lazy.with_index.to_a, [1, 2, 3].lazy.with_index(1).to_a, [1, 2, 3].lazy.with_index { |x, i| [x, i] }.to_a, [1, 2, 3].lazy.each_with_index.map { |x, i| x * i }.to_a
p [1, 2].lazy.zip([3, 4], [5]).to_a, [1, 2].lazy.zip([3, 4]) { |a| p a }, [[1, 2], [3, 4]].lazy.map { |a, b| a + b }.to_a, { a: 1 }.lazy.map { |k, v| [k, v] }.to_a
p [1, 2].lazy.flat_map { |x| [x] * x }.to_a, [1, 2].lazy.flat_map { |x| x }.to_a, [1, 2].lazy.flat_map { |x| [x].lazy.map { |y| y * 10 } }.to_a, [[1, [2]], 3].lazy.flat_map(&:itself).to_a
p [1, 2].lazy.collect { |x| x }.to_a, [1, 2].lazy.collect_concat { |x| [x] }.to_a, [1, 2].lazy.filter(&:odd?).to_a, [1, 2].lazy.find_all(&:odd?).to_a
ml = Enumerator.new { |y| y.yield 1, 2; y.yield 3 }.lazy
p ml.map { |a, b| [a, b] }.to_a, ml.map { |x| x }.to_a, ml.to_a, ml.select { |a| a }.to_a, ml.each { |*a| p a }
%i[map select reject filter_map take_while drop_while flat_map].each do |m|
  [1].lazy.__send__(m)
rescue ArgumentError => x
  p x.message
end
begin
  [1].lazy.take(-1)
rescue ArgumentError => x
  p x.message
end
begin
  [1].lazy.drop(-1)
rescue ArgumentError => x
  p x.message
end
begin
  Enumerator::Lazy.new([1])
rescue ArgumentError => x
  p x.message
end
custom = Enumerator::Lazy.new([1, 2, 3]) { |y, v| y << v * 100 if v.odd? }
p custom, custom.to_a, custom.size, Enumerator::Lazy.new([1], 7) { |y, v| y << v }.size
sized = Enumerator::Lazy.new(1..3, 3) { |y, v| y.yield v, v }
p sized.map { |a, b| a + b }.to_a, sized.eager.to_a
p [1, 2, 3].lazy.map { |x| x * 2 }.each { |x| print x }.class
puts
p [1, 2, 3].lazy.include?(2), [1, 2, 3].lazy.count, [1, 2, 3].lazy.reduce(:+), [1, 2, 3].lazy.min, [3, 1].lazy.sort, [1, 2, 3].lazy.each_slice(2).to_a, [1, 2, 3].lazy.each_cons(2).to_a
p [1, 2, 3].lazy.to_enum(:each_slice, 2), [1, 2, 3].lazy.to_enum(:each_slice, 2).to_a, [1, 2, 3].lazy.enum_for.to_a, [1, 2, 3].each.lazy, (1..3).lazy.map { |x| x }.eager
p [4, 5].lazy.each_entry.to_a, [1, 2].lazy.take(1).lazy.class
side = []
[1, 2, 3].lazy.map { |x| side << x; x }.take(1).to_a
p side
side = []
[1, 2, 3].lazy.map { |x| side << x; x }.take_while { |x| x < 2 }.to_a
p side
side = []
[1, 2, 3].lazy.map { |x| side << x; x }.first(2)
p side
side = []
[1, 2, 3].lazy.map { |x| side << x; x }.take(0).to_a
p side
side = []
[1, 2, 3].lazy.map { |x| side << x; x }.each_slice(2).first(1)
p side
gc = inf.map { |x| GC.start; x.to_s * 2 }.select { |s| s.size > 1 }
p gc.first(30).last
p [1, 2].zip(1..1), [1, 2].zip(3.., [5]), ([1].zip(2) rescue $!), [].zip(Object.new), [1].zip([2]) { |r| p r }, [1, 2].zip({ a: 1 })
class Yields
  def each = yield(1, 2)
  def to_ary = [:ary]
end
p [1, 2].zip(Yields.new), (1..2).zip(3..4), (1..2).each_entry.zip([9]) { |r| p r }
