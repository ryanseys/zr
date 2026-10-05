# enum_yield: values that `each` yields together go to a lambda of two
# parameters spread (rb_yield_force_blockarg); one yielded Array does not.
o = Object.new
def o.each
  yield 1
  yield 2
  yield 3
end
o.extend(Enumerable)
pairs = o.each_with_index
two = ->(x, i) { x + i > 2 }
p pairs.select(&two), pairs.reject(&two), pairs.partition(&two), pairs.sort_by(&->(x, i) { -x })
p pairs.group_by(&->(x, i) { i.odd? }), pairs.min_by(&->(x, i) { -i }), pairs.max_by(&->(x, i) { -i })
p pairs.minmax_by(&->(x, i) { i }), pairs.drop_while(&->(x, i) { i < 1 }), pairs.grep(Array, &->(x, i) { x * i })
seen = []
pairs.each_entry(&->(x, i) { seen << [i, x] })
pairs.cycle(1, &->(x, i) { seen << x })
p seen
got = []
pairs.zip([:a, :b, :c], &->((x, i), y) { got << [x, y, i] })
p got
p(([[1, 2]].sort_by(&->(a, b) { a }) rescue $!))
p [[1, :a], [2, :b]].partition { |_, t| t == :a }, [[1, 2]].each_entry.to_a
def o.each(foo:) = yield(foo)
p o.to_a(foo: 1)
p(([1].tally(BasicObject.new) rescue $!.class), ([1].tally(nil) rescue $!.class))
regexp = Regexp.new("x")
def regexp.===(other) = true
p [1, 2].grep(regexp)
