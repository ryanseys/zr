def i(x, y = 2, *r, z, k: 0, **kw, &b); [x, y, r, z, k, kw, b]; end
p i(1, 9), i(1, 2, 3, 4, 5, k: 6, m: 7)
begin; i; rescue ArgumentError => e; p e.message; end
def j(x, y = 1); [x, y]; end
p j(1), j(1, 2)
begin; j(1,2,3); rescue ArgumentError => e; p e.message; end
def k(h); h; end
p k(a: 1), k({a: 1})
def l(a, k: 1); [a, k]; end
p l({z: 1}), l(1, k: 2)
begin; l(1, 2); rescue ArgumentError => e; p e.message; end
def m(**kw); kw; end
p m, m(a: 1), m(**{b: 2}, c: 3)
p [1, *[2, 3], *nil, 4]
def n(*a); a; end
p n(*[1, 2], 3), n(*nil), n
def f(a:); a; end
begin; f(b: 1); rescue ArgumentError => e; p e.message; end
begin; f; rescue ArgumentError => e; p e.message; end
def g(a:, b:); end
begin; g; rescue ArgumentError => e; p e.message; end
def h(a: 1); a; end
begin; h(x: 1, y: 2); rescue ArgumentError => e; p e.message; end
p h, h(a: 5)
def yielder; yield 1, 2, 3; end
yielder { |a, *r| p [a, r] }
yielder { |a, b = 9, c, d| p [a, b, c, d] }
[[1, 2]].each { |a, b| p [a, b] }
[[1, 2]].each { |a| p a }
[[1, 2]].each { |*a| p a }
[[1, 2]].each { |a, | p a }
def with_block(&b) = b
p with_block.nil?, with_block { 1 }.class
def pass(&b) = [1, 2].map(&b)
p pass { |x| x * 3 }, [1, 2].map(&:to_s), %w[a b].map(&:upcase)
def spl(*args) = yield(*args)
p spl(1, 2) { |a, b| a + b }
def r2 = return 1, 2
p r2
p [1, 2].each { |x| break x, x if x == 2 }
def opt_ref(a, b = a * 2, c = b + 1) = [a, b, c]
p opt_ref(1), opt_ref(1, 5), opt_ref(1, 5, 9)
x = { **{ a: 1 }, b: 2, **{ c: 3 } }
p x
begin; [1].map(&5); rescue TypeError => e; p e.message; end
p [3, 1, 2].select(&:odd?)
