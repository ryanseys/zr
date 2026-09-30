# A Hash of eight entries or fewer scans its entries; past eight it
# indexes them. Every operation agrees across the border, with
# deletes, a rehash, compare_by_identity, a copy and keys whose eql?
# adds to the table on the way.
h = {}
(1..12).each { |i| h["k#{i}"] = i; p [h.size, h["k1"], h["k#{i}"], h.key?("k0")] if [1, 8, 9, 12].include?(i) }
9.times { |i| h.delete("k#{i + 1}") }
p h, h["k10"], h.key?("k3")
h["a"] = 1
h.rehash
p h.keys, h.to_a.last
c = h.dup
c["z"] = 26
p h.size, c.size, c["z"], h["z"]
s = { 1 => :a, 2.0 => :b, :c => 3, "d" => 4, [5] => 5, nil => 6, true => 7 }
p s[1], s[2.0], s[2], s[:c], s["d"], s[[5]], s[nil], s[true], s.size
s.compare_by_identity
k = "d"
s[k] = 8
p s[k], s["d"], s.size
class Adder
  attr_reader :n
  def initialize(n, h) = (@n = n; @h = h)
  def hash = n.hash
  def eql?(o) = (@h[Object.new] = 1; o.is_a?(Adder) && o.n == n)
end
t = {}
t[Adder.new(1, t)] = :one
p t[Adder.new(1, t)], t.size > 1
u = {}
3.times { |i| u[i] = i }
u.delete(1)
u[1] = :back
p u, u.first, u.min_by { |k, v| k.to_s }
p({ a: 1 }.merge(b: 2).select { |k, v| v > 1 }, { x: 1 }.compare_by_identity.key?(:x))

