# Enumerable methods that yield each step's values as each gave them
# (rb_yield_values2), as ruby's count, flat_map, filter_map and the
# predicates do; a Hash still yields each pair as one Array.
e = [5, 6].each_with_index
p e.count { |a| a > 5 }, e.flat_map(&:*), e.filter_map { |a| a if a > 5 }, e.any? { |a| a > 5 }, e.all? { |a, i| i < 2 }, e.none? { |a| a > 9 }, e.one? { |a| a == 6 }
p e.take_while { |a| a < 6 }, e.find_index { |a| a == 6 }, e.uniq { |a, i| a % 2 }, e.to_h { |a, i| [a, i] }, e.collect_concat { |a, i| [a, i] }
h = {a: 1, b: 2}
p h.count { |k, v| v > 1 }, h.flat_map { |k, v| [k] }, h.filter_map { |pair| pair }, h.any? { |pair| pair.is_a?(Array) }, h.uniq { |k, v| v % 1 }, h.to_h { |k, v| [v, k] }, h.find_index { |k, v| v == 2 }, h.take_while { |pair| pair[1] < 2 }
gen = Enumerator.new { |y| y.yield 1, 2; y.yield 3; y.yield }
p gen.count { |a| a }, gen.filter_map { |a, b| b }, gen.flat_map { |*a| a }, gen.find_index { |a, b| b == 2 }, gen.uniq { |a| a }, gen.to_h { |a, b| [a, b] }
p [[1, 2], [3, 4]].each.count { |a, b| b > 2 }, (1..3).each_slice(2).flat_map { |a, b| [b] }

# find and select force the pair into a lambda of more than one
# positional parameter, an optional one included (rb_yield_force_blockarg).
got = []
lo = ->(k, v = 0) { got << [k, v]; v }
lr = ->(*a) { got << a; false }
p h.find(&lo), h.find(&lr), h.select(&lo), got
