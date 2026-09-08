# frozen_string_literal: true

# `using M` turns M's refinements on for the rest of the LEXICAL scope that
# wrote it -- the file, or the class body -- so a byte RANGE is the rule. A
# `def` written below the `using` is covered, one written above it is not.
#
# WHICH classes M refines is a run-time fact, so the site names neither the
# module nor the holder: it takes an activation slot, fills it where the
# `using` runs, and every call the range covers hands its slots over.

module Sizes
  refine Array do
    def second = self[1]
    def pair = [first, second]
  end
  refine String do
    def shout = upcase + "!"
  end
  refine Integer do
    def +(other) = 999
  end
end

module ClassSide
  refine Array.singleton_class do
    def pairs(n) = Array.new(n) { |i| [i, i] }
  end
end

def before = [1, 2].respond_to?(:second)
p before

using Sizes

p [1, 2, 3].second
p [1, 2, 3].pair
p "hi".shout
p 1 + 2
p [1, 2].respond_to?(:second)
p [1, 2].send(:second)
p [1, 2].method(:second).call
p [1, 2].method(:second).owner

# A `def` below the `using` is covered wherever it runs.
def through(a) = a.second
def reflected(a) = a.method(:second).call
p through([4, 5])
p reflected([4, 5])

# Safe navigation, a splat and a block argument all reach the refined body.
p [7, 8]&.second
def spread(*a) = a.second
p spread(9, 10)
p [[1, 2], [3, 4]].map { |a| a.second }

using ClassSide
p Array.pairs(2)

# A class body scopes its own `using` to that body.
class Narrow
  using Sizes
  def take(a) = a.second
end
class Wide
  def take(a) = a.respond_to?(:second)
end
p Narrow.new.take([11, 12])
p Wide.new.take([11, 12])

# A `using` under a guard covers the rest of the body either way; one whose
# guard does not run leaves its slot empty, which activates nothing.
module Never
  refine Integer do
    def nope = :nope
  end
end
using Never if RUBY_VERSION.to_i > 99
begin
  p 1.nope
rescue NoMethodError
  puts "NoMethodError"
end
__END__
false
2
[1, 2]
"HI!"
999
true
2
2
#<refinement:Array@Sizes>
5
5
8
10
[2, 4]
[[0, 0], [1, 1]]
12
true
NoMethodError
