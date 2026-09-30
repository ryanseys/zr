p((1..4).minmax_by { -_1 })
p(%w[a bb cc d].minmax_by(&:size))
p([].minmax_by { _1 })
p([5].minmax_by { _1 })
p(%w[x y z].minmax_by { 0 })
p(%w[p q r s t].minmax_by { |w| w == "q" || w == "s" ? 1 : 0 })
p({foo: 0, bar: 1, baz: 2}.minmax_by { |k, v| -v })
p([3, 1, 2].each.minmax_by { _1 })
p((1..3).minmax_by.size)
begin; [1, "a"].minmax_by { _1 }; rescue => e; p e.class, e.message; end
p [1, 2, 3].inject(:+), (1..4).reduce(10) { _1 * _2 }, [[1, 2]].inject { break 9 }
p (1..3).each_slice(2).to_a, (1..3).each_cons(5).to_a
o = Object.new
def o.each = (yield 1; yield 2)
def o.size = 1
o.extend(Enumerable)
p o.each_cons(2).to_a
p o.each_cons(2) { p :never }.equal?(o)
p o.collect_concat { [_1, _1] }, o.collect { _1 * 3 }, o.min, o.max(1), o.zip([3]), o.uniq, o.entries
p o.minmax_by { -_1 }, o.reverse_each.to_a, o.cycle.first(3)

