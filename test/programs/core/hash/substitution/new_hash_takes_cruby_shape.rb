# A new Hash takes the shape CRuby gives it. Hash[] builds the
# receiver's class and keeps neither the identity flag nor the default;
# select, reject, slice, except and transform_values keep the identity
# flag and no default; compact, merge, dup and clone copy the whole
# Hash. replace takes the other's contents, default and identity flag,
# and leaves itself alone. A key's own hash and eql? decide, a Bignum
# hash folded, whatever the key's class.
def t = yield rescue [$!.class, $!.message]

class HS < Hash; end
h = {a: 1}
i = {}.compare_by_identity
d = Hash.new(3)
d[:a] = nil
d[:b] = 1
p t { Hash[h].equal?(h) }, t { HS[{a: 1}].class }, t { HS[[[:a, 1]]].class }, t { Hash[i].compare_by_identity? }, t { Hash[d][:zz] }
p t { [i.select { true }, i.reject { false }, i.slice, i.except, i.compact, i.transform_values { 1 }, i.merge({}), i.dup, i.clone].map(&:compare_by_identity?) }
p t { [d.compact, d.select { true }, d.reject { false }, d.slice(:b), d.except(:a), d.transform_values { 1 }, d.merge({})].map { |x| x[:zz] } }
p t { [HS[a: 1].select { true }, HS[a: 1].reject { false }, HS[a: 1].slice(:a), HS[a: 1].except, HS[a: 1].compact, HS[a: 1].transform_values { 1 }, HS[a: 1].merge({})].map(&:class) }
p t { h.replace(h) }, t { g = {}; g.replace(Hash.new(5)); g[:x] }, t { {}.replace(i).compare_by_identity? }, t { i.dup.replace({a: 1}).compare_by_identity? }
p t { {}.freeze.replace({}) }, t { x = {a: 1}; x.each { x.replace({}) } }, t { x = {a: 1}; x.each { x.compare_by_identity } }, t { {}.freeze.merge!({}) }

k = Class.new { def hash = 2**70; def eql?(o) = true }
e = Class.new(StandardError) { def hash = 1; def eql?(o) = true }
p t { {k.new => 1}[k.new] }, t { {e.new => 1}[e.new] }, t { {Class => 1}[Class] }, t { {1..2 => :r}[1..2] }

