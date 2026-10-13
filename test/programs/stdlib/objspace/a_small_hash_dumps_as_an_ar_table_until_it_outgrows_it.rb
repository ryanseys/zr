# ruby 4.1's ObjectSpace.dump says "ar_table":true for a Hash that keeps
# its pairs in its own slot: two in a new Hash, which a third pair or a
# capacity past two moves to an st_table for good, a clear included.
require "objspace"
def d(h) = ObjectSpace.dump(h).include?('"ar_table":true') ? :ar : :st
h = {}
r = []
1.upto(9) { |i| h[i] = i; r << d(h) }
p r
h.clear
p d(h)
p [d({}), d({a: 1}), d({a: 1, b: 2}), d(Hash.new(1)), d(Hash.new {}), d(Hash.new(capacity: 2)), d(Hash.new(capacity: 7))]
p [d({}.compare_by_identity), d({a: 1}.merge(b: 2)), d((1..20).to_h { [_1, 1] }.slice(1)), d((1..20).to_h { [_1, 1] })]
