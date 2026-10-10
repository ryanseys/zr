h = { a: 1, "b" => 2, 3 => 4, 1.5 => 5, [1, 2] => 6, nil => 7 }
p h, h[:a], h["b"], h[3], h[1.5], h[[1, 2]], h[nil], h[:zz], h.size
k = [1]; g = { k => "v" }; k << 2; p g[k], g[[1]], g.rehash[[1, 2]], g[k]
p({ 0.0 => "a" }[-0.0], { -0.0 => "a" }[0.0], { 1 => 1 }[1.0], { 1.0 => 1 }[1], 0.0.eql?(-0.0), 0.0.hash == -0.0.hash)
big = {}; 4000.times { |i| big[[i % 40, i / 40]] = i }; p big.size, big[[7, 3]], big[[39, 99]], big[[40, 0]]
s = {}; 5000.times { |i| s["k#{i}"] = i }; p s.size, s["k4999"], s["k0"], s.key?("k2500"), s.delete("k2500"), s.key?("k2500"), s.size
d = { a: 1, b: 2 }; d.delete(:a); d[:c] = 3; p d, d.keys, d.to_a, d.first, d.min_by { |k, v| v }
e = { a: 1, b: 2, c: 3 }
begin; e.each { |k, v| e[:d] = 4 }; rescue RuntimeError => x; p x.message; end
e.each { |k, v| e[:a] = 9 }; p e
begin; e.each { |k, v| e.store(:zz, 1) }; rescue RuntimeError => x; p x.message; end
p e.size
f = { a: 1 }.compare_by_identity; f["x"] = 1; f["x"] = 2; p f.size, f[:a], f["x"], f.compare_by_identity?
i = {}; o = Object.new; i[o] = 1; p i[o], i[Object.new]
c = { a: 1 }; c2 = c.dup; c2[:b] = 2; p c, c2
w = { 1 => 2 }; 100.times { |n| w[n] = n; w.delete(n) if n.odd? }; p w.size, w[50], w[51], w.keys.first(3)
p({ a: 1 }.hash == { a: 1 }.hash, { a: 1 }.eql?({ a: 1 }), { { a: 1 } => 1 }[{ a: 1 }], { [1, [2]] => 3 }[[1, [2]]], { "a" => 1 }["a".dup], { :a => 1 }[:a], { 2**40 => 1 }[2**40])
class Boom; def hash = raise("from hash"); def eql?(_o) = true; end
hh = { 1 => :one }
begin; hh[Boom.new]; rescue RuntimeError => x; p [x.class.to_s, x.message]; end
begin; hh[Boom.new] = :two; rescue RuntimeError => x; p x.message; end
begin; hh.fetch(Boom.new); rescue RuntimeError => x; p x.message; end
p hh.size
gd = Hash.new { |hash, key| hash[key] = key * 2 }
gd["a"] = "x"
p gd.default, gd.default("q"), gd["zz"], gd.dup["yy"], gd.clone["xx"], gd.merge({})["ss"], Hash.new(7).default, Hash.new(7).default(:k), Hash.new(7)[:k], (gd.default(1, 2) rescue $!.message)
dd = { a: 1 }; p dd.delete(:a) { |k| "gone #{k}" }, dd.delete(:z) { |k| "gone #{k}" }, dd.delete(:z), dd
p [1, 1, 2].tally, [1, 2].tally({ 1 => 5 }), ([1].tally(1) rescue $!.message), ([1].tally({}.freeze) rescue $!.class), 12.gcdlcm(18), 4.gcdlcm(6)
hm = { a: 1, b: 2 }
p hm.any? { |pair| pair[1] > 1 }, hm.any? { |k, v| v > 1 }, hm.count { |pair| pair[1] > 1 }, hm.all? { |pair| pair[1] > 0 }, hm.any?([:a, 1]), hm.any?([:a, 2]), hm.sort { |x, y| y[1] <=> x[1] }, hm.min_by { |k, v| -v }, hm.each_slice(1).to_a, hm.find_index([:b, 2]), hm.each_entry { |x| x }.class, hm.first, hm.first(1)
r = (1..5)
p r.sort, r.sort { |a, b| b <=> a }, r.grep(2..4), r.min { |a, b| b <=> a }, r.minmax, [3, 1, 2].sort { |a, b| b <=> a }, (1..3).sort_by { |x| -x }, (1..3).max(2), (1..3).sum
sk = {}; ("a".."zz").each_with_index { |x, idx| sk[x] = idx }; p sk.size, sk["zz"], sk["ab"], sk.count, sk.keys.last
sym = {}; 2000.times { |n| sym[:"s#{n}"] = n }; p sym[:s1999], sym.size, sym.values.sum
mixed = { 1 => :i, 1.0 => :f, "1" => :s, :"1" => :y, [1] => :a, nil => :n, true => :t }
p mixed.size, mixed[1], mixed[1.0], mixed["1"], mixed[:"1"], mixed[[1]], mixed[nil], mixed[true], mixed[false]
