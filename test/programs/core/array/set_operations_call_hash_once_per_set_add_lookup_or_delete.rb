# Array#uniq, uniq!, |, &, -, union, difference and intersect? hash an
# element once each time ruby's hidden Set adds, finds or deletes it, and
# not at all where both arrays are short (16 or fewer) and compare by
# eql?. uniq of one element is a copy, with no call of the block.
$hashes = 0

class K
  attr_reader :v

  def initialize(v) = @v = v

  def hash
    $hashes += 1
    @v.hash
  end

  def eql?(other) = other.is_a?(K) && @v.eql?(other.v)
  def inspect = "K(#{@v.inspect})"
end

def ks(n, mod = n) = (0...n).map { |i| K.new(i % mod) }

def calls
  $hashes = 0
  result = yield
  [result.is_a?(Array) ? result.size : result, $hashes]
end

p calls { [K.new(1), K.new(2), K.new(1), K.new(1.0), K.new(2), 3].uniq }
p calls { ks(1).uniq }, calls { ks(2).uniq }, calls { ks(40, 7).uniq }
p calls { ks(40, 7).uniq! }, calls { ks(7).uniq! }, calls { ks(1).uniq! }
p calls { ks(8) | ks(8) }, calls { ks(9) | ks(8) }, calls { ks(40, 7) | ks(30, 5) }
p calls { ks(16) & ks(16) }, calls { ks(17) & ks(3) }, calls { ks(40, 7) & ks(30, 5) }
p calls { ks(100) - ks(16) }, calls { ks(100) - ks(17) }, calls { ks(16) - ks(100) }
p calls { ks(10).union(ks(3), ks(3)) }, calls { ks(10).union(ks(7)) }
p calls { ks(20).difference(ks(17), ks(3)) }, calls { ks(16).difference(ks(17)) }
p calls { ks(16).intersect?(ks(16)) }, calls { ks(17).intersect?(ks(3)) }, calls { ks(3).intersect?(ks(17)) }
p calls { ks(20).intersection(ks(20), ks(2)) }

yielded = []
p [K.new(1)].uniq { |x| yielded << x }, yielded
p [1, 2, 3, 4].uniq(&:odd?), [1, 1].uniq!, [1, 2].uniq!
words = %w[b a b c a]
p words.uniq, words.uniq.map(&:frozen?), (words | %w[d]).last.frozen?
big = (1..20).map(&:to_s)
p (big | big).size, (big & big.reverse).first(3), (big - big.first(18)), big.intersect?(%w[20 x])
p [1, 1.0, 1r] | [1.0], [1, 1.0] & [1.0, 1], [0.0, -0.0].uniq, [Float::NAN, Float::NAN].uniq.size
