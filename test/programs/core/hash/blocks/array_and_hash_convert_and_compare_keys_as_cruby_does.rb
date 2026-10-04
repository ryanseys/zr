# Array methods convert elements with to_ary and to_str and warn for an
# unused block; a Hash lookup asks the key it looks up for eql?; and
# Hash.ruby2_keywords_hash keeps the class, ivars, default and identity.
a = [1, 2, 3]
p a.count(1) { true }, a.index(2) { false }, a.rindex(3) { false }
$VERBOSE = nil
p a.count(1) { true }
$VERBOSE = false
ta = Object.new
def ta.to_ary = [2, 3]
p [1, ta].assoc(2), [1, ta].rassoc(3), [2, 3] <=> ta, [ta].to_h
s = Object.new
def s.to_str = "2"
p %w[a b c] * s
n = Object.new
def n.to_str = nil
def n.to_ary = ["foo"]
m = Object.new
def m.to_str = nil
def m.to_ary = nil
def m.to_s = "bar"
p [n].join, [m].join, [n, m] * "-"
x = Object.new
def x.hash = 0
y = Object.new
def y.hash = 0
def y.eql?(o) = ($calls = ($calls || 0) + 1; true)
h = { x => 1 }
p h[y], h.key?(y), $calls
class MyHash < Hash; end
h = MyHash.new(1)
h.instance_variable_set(:@x, 42)
h.compare_by_identity
r = Hash.ruby2_keywords_hash(h)
p r.class, r.instance_variable_get(:@x), r[:nope], r.compare_by_identity?, Hash.ruby2_keywords_hash?(r), Hash.ruby2_keywords_hash?(h)
d = Hash.new { |_, k| k * 2 }
p Hash.ruby2_keywords_hash(d)[3]
def kw(**k) = k
def pass(*a) = kw(*a)
p pass(Hash.ruby2_keywords_hash({ a: 1 }))
