# Range, Comparable, Enumerator.produce and Proc#inspect batch (native only: Enumerator#next).
def t; yield; rescue RangeError, TypeError, ArgumentError => e; [e.class, e.message]; end
p t { (1..).max }, t { (1...).max }, t { (1.0..).max }, t { (..5).min }, (1..).min
p (1..5).frozen?, Range.new(1, 2).frozen?, (1..5).dup.frozen?
p ("a".."e").count, ("a"..."e").count, ("aa".."ad").count, ("a".."e").count { |s| s < "c" }, ("a".."e").count("b"), (1..5).count { |i| i.even? }
p (1..5).cover?(2..4), (1..5).cover?(0..4), (1..5).cover?(2..6), (1..5) === (2..4), (1..5) === (1..5), (1...5) === (2..5), (1..5).include?(2..4), (1..5).member?(2..4)
p t { (1..5).cover?("x") }, t { (1..5).include?("x") }, t { (1..5) === "x" }, t { (1..5).first("x") }, t { (1..5).each_slice("x") { } }, (1..5).eql?(1.0..5.0), (1..5) == (1.0..5.0)
p (5..1).min, (5..1).max, (5..1).minmax, (1...1).min, (1..5).minmax, (1..10).step(3) { |x| }.class
p t { (1..5).first(-1) }, t { (1..5).last(-1) }, t { (1..5).min(-1) }, t { (1..5).max(-1) }, t { ("a".."e").first(-1) }
p (..5).max, t { (..5).first }, t { (1..).last }, t { (1..).minmax }, t { (..5).to_a }, (1..).size
p (1..).min(3), (5..).min(2), (1..).min(0), t { (1..).last(2) }, t { (1..).to_a }
p (..5).max(2), (..5).max(3), (...5).max, (...5).max(3), (..5).max(0), (..5.0).max, t { (...5.0).max }, t { (..5.0).max(2) }
p t { (1..).min { |a, b| a <=> b } }, t { (1..).min(3) { |a, b| a <=> b } }, t { (..5).max { |a, b| a <=> b } }
p (1..5).min(2), (1..5).max(2), (1...5).max(2), (1..5).min(9), (1..5).max(9), (1..5).min(2) { |a, b| b <=> a }, (1..5).max(2) { |a, b| b <=> a }, (5..1).min(2), (5..1).max(2), ("a".."e").min(2)
p (..5).reverse_each.first(3), (..5).reverse_each.class
p t { (1..).count }
p(Enumerator.produce(1) { |n| n * 2 }.take(3))
p(Enumerator.produce(1) { |n| n + 1 }.first(4))
g = Enumerator.produce(0) { |n| n + 2 }
p g.next, g.next
e = Enumerator.produce { |n| (n || 0) + 1 }
p e.take(3), e.size, e.inspect.start_with?("#<Enumerator: #<Enumerator::Producer:0x"), e.class
p Enumerator.produce(1) { |n| raise StopIteration if n > 4; n + 1 }.to_a
p Enumerator.produce([1, 1]) { |a, b| [b, a + b] }.lazy.map(&:first).first(6)
class W; include Comparable; def <=>(o) = nil; end
[W.new, 1, "s", nil, 1.5, :s, true].each { |o| begin; W.new < o; rescue ArgumentError => e; puts e.message; end }
x = "a"
p(begin; [1, x, 2].min; rescue => e; e.message; end)
p(begin; [1, x, 2].max; rescue => e; e.message; end)
p(begin; Rational(1, 2) < x; rescue => e; e.message; end)
pr = proc { }
l = lambda { }
s = :x.to_proc
m = 1.method(:+).to_proc
[pr, l, s, m, pr.to_s, proc {}.curry, ->(a) {}.curry, proc { |&b| }].each { |x| puts x.inspect.gsub(/0x\h+/, "X").gsub(%r{/\S*/}, "") }
class Q; def initialize(b) = @b = b; end
puts Q.new(pr).inspect.gsub(/0x\h+/, "X").gsub(%r{/\S*/}, "")
p 5[0, 2], 255[0..3], 255[4..], (-2)[0], 255[2...4], 255[-1..2], 255[3..1], 5[-1], 5[1, 0], 255[..-1], 255[-2..-1], 5[1, -1], 0[..3], 0b1011[0]
begin; 255[..3]; rescue ArgumentError => e; p e.message; end
[[1, "a"], [1, nil], [nil, nil], ["a", 1.0], [1, Object.new]].each do |a, b|
  begin; p Range.new(a, b).class; rescue ArgumentError => e; p e.message; end
end
x = "a"
begin; (1..x); rescue ArgumentError => e; p e.message; end
p rand(2.0...2.0), rand(3.0..1.0), rand(1..1)
begin; rand(1..); rescue Errno::EDOM => e; p e.message; end
begin; [1, 2, 3][1e300]; rescue RangeError => e; p e.message; end
begin; [1, 2, 3].first(-1e30); rescue RangeError => e; p e.message; end
p [1, 2, 3][1e18], [1, 2, 3][2.9]
