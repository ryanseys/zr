# Edge cases of Array methods that answer as ruby's do.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

# index(nil) and find_index(nil) search for nil; no argument and no block
# is an Enumerator.
t { [1, 2, nil, 4].index(nil) }
t { [1, nil].find_index(nil) }
t { [nil].each.find_index(nil) }
t { [1, 2].index.class }
t { [1, nil, 3].rindex(nil) }
t { [1].rindex.class }

# An operand with to_ary decides ==, as ruby asks it.
class ArrayLike
  def to_ary = [1]
  def ==(other) = other == [1]
end
t { [1] == ArrayLike.new }
t { [2] == ArrayLike.new }
t { [1].eql?(ArrayLike.new) }

# The Enumerator of permutation shows only the count that was given.
t { [1, 2].permutation.inspect }
t { [1, 2].permutation(1).inspect }
t { [1, 2].cycle(nil).inspect }

# A frozen receiver raises before the index is read.
t { [1].freeze.slice!(5) }
t { [].freeze.map! { 1 } }
t { [].freeze.collect! { 1 } }

# rfind follows a receiver that shrinks under its walk.
seen = []
a = [4, 2, 1, 5, 1, 3]
t { a.rfind { |x| seen << x; a.clear; false } }
t { seen }

# fetch yields the index it was given, and names 1..2 arguments.
t { [10, 20].fetch(5.5) { |i| i } }
t { [].fetch }
