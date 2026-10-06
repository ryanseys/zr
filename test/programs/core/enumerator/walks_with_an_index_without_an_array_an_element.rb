# with_index, each_with_index and with_object pack what `each` yields
# as rb_enum_values_pack packs it -- one value through, several as an
# Array, none as nil -- put the index or the memo beside it, and hand
# the block's own answer back to `each`, which is what each of the
# three answers in turn.
a = [1, 2, 3]
p a.each.with_index { |x, i| }
p a.map.with_index { |x, i| x * 2 }
p a.each_with_index.with_index { |(x, i), j| }
p a.each.with_index(5).to_a
p({ x: 1, y: 2 }.each.with_index { |(k, v), i| p [k, v, i] })
p a.each.with_object(:m) { |x, m| }
p a.each.each_with_index { |x, i| }
p [[1, 2], [3, 4]].each.with_index { |v, i| p [v, i] }
p [].each.with_index { |x, i| }
e = Enumerator.new { |y| y.yield(1, 2); y << 3 }
e.with_index { |v, i| p [v, i] }
p e.with_object([]) { |v, m| m << v }
p a.each.with_index.to_a
p a.map.with_index { |x, i| i }
p a.select.with_index { |x, i| i > 0 }
p a.each_slice(2).with_index { |s, i| p [s, i] }
p({ x: 1 }.each_pair.with_object({}) { |(k, v), m| m[k] = v })
p a.each_with_object([]) { |x, m| m << x }
p a.each.with_index(-2).to_a
idx = a.map.with_index(10) { |x, i| [x, i] }
p idx
p a.each.with_index { |x, i| next :skip if i.zero?; x }
