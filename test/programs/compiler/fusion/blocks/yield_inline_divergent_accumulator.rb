# A yield-inlined method that accumulates yield results into an array it
# returns (map-style) must hold any value type when its callers pass blocks
# of divergent value type, so an object-returning block's elements keep
# their objects. The scalar round-trip
# for a method that returns the yield value directly is unaffected.
class Rel
  def map
    out = []
    [1, 2].each { |i| out << (yield i) }
    out
  end
end
class T
  attr_accessor :n
  def initialize(n); @n = n; end
end
def sum_ints; Rel.new.map { |i| i * 2 }; end
def make_objs(counts); Rel.new.map { |i| o = T.new(counts[i]); o }; end
def make_strs; Rel.new.map { |i| "v#{i}" }; end
p sum_ints
p make_objs({ 1 => 10, 2 => 20 }).map { |o| o.n }
p make_strs
