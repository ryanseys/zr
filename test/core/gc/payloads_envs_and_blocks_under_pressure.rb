# Large payloads, kept Envs, escaped blocks, kept each adapters and
# Struct values together across many collections keep their contents.
Point = Struct.new(:x, :y)
keepers = []
adapters = []
class Bag
  include Enumerable
  def each(&b) = (@b = b; [1, 2, 3].each(&b))
  def replay = [4].each(&@b)
end
big = []
200.times do |i|
  s = "x" * 100_000
  s << i.to_s
  big << s if i % 20 == 0
  keepers << proc { |v| [i, v, s.size] } if i % 50 == 0
  bag = Bag.new
  bag.select { |v| v > 1 }
  adapters << bag if i % 50 == 0
  Point.new(i, [i] * 1000)
  Array.new(5000) { |k| k.to_s }
end
GC.start
p big.map(&:size), big.map { |s| s[-3..] }, keepers.map { |k| k.call(7) }, adapters.map(&:replay)
p GC.stat[:count] > 3, Point.new(1, 2).to_a, keepers.size, ObjectSpace.each_object(Bag).count >= 4
pairs = (1..50_000).map { |i| [i, i.to_s] }
h = pairs.to_h
GC.start
p h.size, h[25_000], h.keys.sum, pairs.last, h.select { |k, v| k % 10_000 == 0 }.keys

__END__
[100001, 100002, 100002, 100002, 100002, 100003, 100003, 100003, 100003, 100003]
["xx0", "x20", "x40", "x60", "x80", "100", "120", "140", "160", "180"]
[[0, 7, 100001], [50, 7, 100002], [100, 7, 100003], [150, 7, 100003]]
[[4], [4], [4], [4]]
true
[1, 2]
4
true
50000
"25000"
1250025000
[50000, "50000"]
[10000, 20000, 30000, 40000, 50000]
