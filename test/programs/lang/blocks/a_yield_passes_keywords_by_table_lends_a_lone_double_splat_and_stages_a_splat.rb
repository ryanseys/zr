# A yield passes its keywords as a call does: k: v pairs by a table, a
# lone **h lent to the block, and a splat staged on the spread stack, with
# the block's own rules for spreading and keywords.
def y0 = yield
def y1(*a) = yield(*a)
def yk = yield(a: 2, b: 3)
def yh(h) = yield(**h)
def ye = yield(**{})
def ym(h) = yield(1, **h, c: 4)
h = { a: 1 }
p y0 { 1 }, y1(1, 2) { |a, b| [a, b] }, y1([1, 2]) { |a, b| [a, b] }, y1 { |*a| a }
p yk { |a:, b:| [a, b] }, yk { |**k| k }, yk { |x| x }, yk { |*x| x }, yk { |x, y| [x, y] }
p yh(h) { |a: 0| a }, yh(h) { |**k| k[:z] = 1; k }, h, yh(h) { |x| x }, yh({}) { |*x| x }
p ye { |*x| x }, ye { |x = 5| x }, ye { |x| x }
p ym(h) { |x, **k| [x, k] }, h
p [[1, 2]].each { |a, b| }.size, [1].map { |x, **k| [x, k] }
pr = proc { |a, **k| [a, k] }
p y1([1, {b: 2}], &pr), yk(&pr), yh(h, &pr)
l = ->(a: 0) { a }
p yk(&->(a:, b:) { a + b }), yh(h, &l), (yk(&l) rescue $!.class)
def ys = yield(*[1, 2], k: 1)
p ys { |a, b, k:| [a, b, k] }, ys { |*a, **k| [a, k] }
p y1(*[1, {a: 2}]) { |x, a: 0| [x, a] }
def yy(*a) = yield(*a, **{})
p yy(1, 2) { |*a| a }
ruby2_keywords def yr(*a) = yield(*a)
p yr(1, k: 2) { |x, k:| [x, k] }
def each_kv = yield(:k, 1)
p each_kv { |k, v| [k, v] }
p [1,2].each_slice(1).to_a, {a: 1}.map { |k, v| [k, v] }, {a: 1}.each { |*x| p x }
