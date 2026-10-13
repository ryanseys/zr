# An Array that the conversion of an argument shrinks: sample draws past
# what is left sample nothing, values_at reads a range-like object's ends
# against the length from before the call, and a slice whose start is
# past the new end is empty ([Bug #22325]). The usual paths stay.
$stdout.sync = true
def try(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end
ary = (1..1_000).to_a
obj = Object.new
obj.define_singleton_method(:to_int) { ary.replace((1..50).to_a); 10 }
gen = Object.new
def gen.rand(lim) = 49
try(:sample1) { ary.sample(obj, random: gen) }
ary = (1..100).to_a
obj = Object.new
obj.define_singleton_method(:to_int) { ary.replace(Array.new(10) { :x }); 10 }
gen = Object.new
gen.define_singleton_method(:rand) { |lim| 8 }
try(:sample2) { ary.sample(obj, random: gen) }
a = (0..100_000).to_a
o = Object.new
o.define_singleton_method(:begin) { a.clear; 0 }
o.define_singleton_method(:end) { 10_000 }
o.define_singleton_method(:exclude_end?) { false }
try(:values_at) { r = a.values_at(o); [r.length, r.compact.size] }
cls = Class.new(Numeric) do
  attr_reader :val
  def initialize(ary, val) = (@ary = ary; @val = val)
  def <=>(other) = val <=> (other.is_a?(self.class) ? other.val : other)
  def to_int = (@ary.clear; val)
  def coerce(other) = [other, val]
end
ary = (1..100).to_a
try(:slice_range) { ary[Range.new(cls.new(ary, 50), cls.new(ary, 60))] }
ary.replace((1..100).to_a)
try(:slice_step) { ary[Range.new(cls.new(ary, 50), cls.new(ary, 60)).step(2)] }
b = [1, 2, 3, 4, 5]
try(:plain_range) { [b[1..2], b[5..6], b[6..7], b[-2..], b[(1..).step(2)], b[(0..10).step(3)]] }
try(:values_at_plain) { b.values_at(0, 2..3, -1, 4..6, -2..-1) }
like = Object.new
def like.begin = 1
def like.end = 2
def like.exclude_end? = true
try(:values_at_like) { b.values_at(like) }
try(:values_at_bad) { b.values_at(Object.new) }
srand(7)
try(:sample_seeded) { [b.sample(3, random: Random.new(42)), b.sample(random: Random.new(1))] }
