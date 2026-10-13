# ruby 4.1 adds the reason to a failed comparison: "comparator returned
# nil" when <=> (or a sort block) gives nil, "coercion was not possible"
# when a number cannot coerce the other side, and "unable to compare
# with zero" when a number has no operator to compare with 0.
def show
  yield
rescue ArgumentError => e
  puts e.message
end

nothing = Object.new
def nothing.<=>(_other) = nil

# <=> gives nil.
show { [3, nil, 1].sort }
show { [3, "a"].max }
show { [3, "a"].min }
show { [3, "a"].minmax }
show { %w[b a].sort { nil } }
show { %w[b a].sort_by { |s| s == "a" ? nil : 1 } }
show { [1, 2].max { nil } }
show { (1..3).max { nil } }
show { [nothing, nothing].sort }
show { [[1, 2], [3]].each_slice(1).sort_by { |(a)| a.size == 2 ? 1 : "x" } }
show { 5.clamp("a", "b") }
show { 5.clamp(nothing, nothing) }
class Shrug
  include Comparable
  def <=>(_other) = nil
end
comparable = Shrug.new
show { comparable < 1 }
show { comparable.between?(1, 2) }
show { comparable.clamp(1, 2) }
show { [1, 2].max_by(2) { |v| v == 1 ? nil : 1 } }

# A number cannot coerce the other side.
show { 1 < "2" }
show { 1.5 >= :x }
show { (2**70) > Object.new }
show { 1.upto("10").to_a }
show { 10.downto(Object.new).to_a }
show { 1.step("5") { } }
show { Rational(1, 2) < nil }

# coerce gives a pair whose operator answers nil.
odd = Object.new
def odd.coerce(other) = [nothing_like(other), other]
def odd.nothing_like(_other) = Class.new { def <(_) = nil; def >(_) = nil }.new
show { 1 < odd }

# No operator to compare with zero.
class NoLess < Numeric
  undef_method :<
end
num = NoLess.new
show { num.negative? }
