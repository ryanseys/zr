# Enumerable#sum adds exactly while it can and, from the first Float,
# with Kahan-Babuska compensation, as Array#sum and CRuby's enum_sum do.
def t = yield rescue [$!.class, $!.message]

p t { {a: 0.1, b: 0.2, c: 0.3}.sum { _2 } }, t { [0.1, 0.2, 0.3].each.sum }, t { (1..3).sum { 0.1 } }
p t { ([0.1] * 10).each.sum }, t { [1, 2, 0.1, 0.2, 0.3].each.sum }, t { [0.1, 1r, 0.2].each.sum }
p t { [1r, 2r].each.sum }, t { [1, 2**70, 3].each.sum }, t { %w[a b].each.sum("") }, t { [[1], [2]].each.sum([]) }
p t { [0.1, Float::INFINITY, 0.2].each.sum }, t { [Float::INFINITY, -Float::INFINITY].each.sum }, t { [0.1, Float::NAN].each.sum }
p t { [1e100, 1.0, -1e100].each.sum }, t { [3, 0.1, 0.2, 0.3].each.sum(0.0) }, t { {x: 1}.sum }

__END__
0.6
0.6
0.30000000000000004
1.0
3.6
1.3
(3/1)
1180591620717411303428
"ab"
[1, 2]
Infinity
NaN
NaN
1.0
3.6
[TypeError, "Array can't be coerced into Integer"]
