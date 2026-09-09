a = [1, 2, 3, 4, 5]
p a.shift, a, a.shift(2), a, [].shift, [].shift(2)
p a.unshift(0, -1), a.prepend(9), a.insert(1, :x, :y), a.insert(-2, :z), a
p a.concat([7], [8, 9]), a.delete_at(0), a.delete_at(-1), a.delete_at(99), a
b = [1, 2, 3, 2, 1]
p b.delete(2), b, b.delete(9), b.delete(9) { :none }, b.delete_if { |x| x == 1 }, b
c = [1, 2, 3, 4, 5, 6]
p c.reject! { |x| x.even? }, c.reject! { |x| x > 100 }, c.select! { |x| x > 1 }, c.keep_if { |x| x < 5 }, c
d = [3, nil, 1, nil]
p d.compact!, d.compact!, [1, 1, 2].uniq!, [1, 2].uniq!, [1, 2, 3].reverse!, [1, 2].clear, [1, 2].replace([3])
e = [1, 2, 3, 4, 5]
p e.slice!(1, 2), e, e.slice!(0), e, e.slice!(1..), e, [1, 2, 3].slice!(5, 1)
p [1, 2].map! { |x| x * 3 }, [[1, [2, [3, [4]]]], 5].flatten, [[1, [2, [3]]]].flatten(1), [1, [2]].flatten!, [1, 2].flatten!
r = [1, 2, 3]
r.reverse_each { |x| print x }
puts
[1, 2, 3, 4, 5].each_slice(2) { |s| p s }
p [1, 2, 3].rotate, [1, 2, 3].rotate(-1), [1, 2, 3].rotate(5), [].rotate
p [1, 2, 3, 4].values_at(0, 2, 5, -1), [[1, [2]]].dig(0, 1, 0), [[1, 2], [3, 4]].assoc(3), [[1, 2]].assoc(9)
p [1, 2] * 2, [1, 2] * ", ", [1, 2, 3] - [2], [1, 2, 2, 3] & [2, 3, 4], [1, 2] | [2, 3]
p [1, 2].zip([3, 4], [5]), [1, 2].product([3, 4]), [1, 2].product, [[1, 2], [3, 4]].transpose
begin
  [[1, 2], [3]].transpose
rescue IndexError => e
  p e
end
p Array.new(3).fill(7), [1, 2, 3].fill { |i| i * i }, [1, 2, 3, 4].fill(0, 1, 2), [3, 1, 2].sort_by! { |x| -x }
p [1, 2, 3].find_index(2), [1, 2, 3].find_index { |x| x > 1 }, [1, 2, 1].rindex(1), [1, 2, 1].rindex { |x| x == 2 }
n = 0
[1, 2].cycle { |x| n += x; break if n > 10 }
p n
p [[1, 2], [3, 4]].to_h, [1, 2].to_h { |x| [x, x * 2] }, [3, 1, 2].minmax, [].minmax
begin
  [1].to_h
rescue TypeError => e
  p e
end
begin
  [[1]].to_h
rescue ArgumentError => e
  p e
end
p [1, [2, [3]]].flatten(-1), [1, 2, 3].take_while { |x| x < 3 }, [1, 2, 3].drop_while { |x| x < 2 }, [1, 2, 3].drop(1)
f = [1, 2].freeze
begin
  f << 3
rescue FrozenError => e
  p e
end
begin
  f.shift
rescue FrozenError => e
  p e
end
begin
  { a: 1 }.freeze[:b] = 2
rescue FrozenError => e
  p e
end
p [1, 2, 3].flat_map { |x| [x, x] }, [1, 2, 3].group_by(&:odd?), [1, 2, 3].partition(&:even?)
p (1..6).each_cons(3).to_a rescue (1..6).each_cons(3) { |c| p c }
p %w[a bb c].min_by(&:size), %w[a bb c].max_by(&:size), [1, 2, 3].one? { |x| x > 2 }, [1, nil].one?, %w[a b a].tally, (1..3).zip([4, 5, 6])
p (1..10).take(3), (1..10).drop(8), (1..3).find_index(2), (1..3).first, (1..3).first(2), [4, 5].each_with_object([]) { |x, m| m << x }
p [3, 1, 2].min, [3, 1, 2].max, (1..4).min, (1..4).max, [3, 1].min { |a, b| b <=> a }, [3, 1, 2].each_entry.to_a rescue p $!
