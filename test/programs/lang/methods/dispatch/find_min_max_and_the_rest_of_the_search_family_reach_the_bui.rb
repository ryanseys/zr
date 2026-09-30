# A builtin Array receiver at a dispatch that exists only because a user class
# defines the same name.
#
# A user candidate takes the block as a real proc, and one proc serves every
# class that the call can reach. On an Array the call runs the builtin method
# with that proc; it does not raise NoMethodError.
#
# The reverse also holds: on the user object the call runs the user method.
# It does not iterate the object as an empty array.

class Rel
  def map
    out = []
    [1, 2].each { |x| out << yield(x) }
    out
  end

  def select
    out = []
    [1, 2, 3].each { |x| out << x if yield(x) }
    out
  end

  def reject
    out = []
    [1, 2, 3].each { |x| out << x unless yield(x) }
    out
  end

  def group_by
    h = {}
    [1, 2, 3, 4].each do |x|
      k = yield(x)
      h[k] = [] unless h.key?(k)
      h[k] << x
    end
    h
  end

  def each
    yield 7
    yield 8
    self
  end

  def find
    yield 1
    :rel_find
  end

  def find_index
    yield 1
    -7
  end

  def min_by
    yield 1
    :rel_min
  end

  def max_by
    yield 1
    :rel_max
  end

  def partition
    yield 1
    [[:a], [:b]]
  end

  def sum
    yield 1
    -8
  end

  def any?
    yield 1
    false
  end

  def all?
    yield 1
    false
  end

  def none?
    yield 1
    false
  end

  def take_while
    yield 1
    [:tw]
  end

  def drop_while
    yield 1
    [:dw]
  end

  def flat_map
    yield 1
    [:fm]
  end

  def each_with_index
    yield 1
    [:ewi]
  end

  # a non-yielding, blockless method of an Enumerable name: the dispatch still
  # exists, and the builtin arm has to materialize the block itself because no
  # candidate asked for one
  def sort_by
    [9]
  end

  def count
    -1
  end
end

def pick(n)
  n == 1 ? Rel.new : [3, 4, 5, 6]
end

p pick(1).find { |x| x > 0 }
p pick(2).find { |x| x > 4 }
p pick(1).find_index { |x| x > 0 }
p pick(2).find_index { |x| x > 4 }
p pick(1).min_by { |x| -x }
p pick(2).min_by { |x| -x }
p pick(1).max_by { |x| -x }
p pick(2).max_by { |x| -x }
p pick(1).partition { |x| x.odd? }
p pick(2).partition { |x| x.odd? }
p pick(1).sum { |x| x }
p pick(2).sum { |x| x * 10 }
p pick(1).any? { |x| x > 0 }
p pick(2).any? { |x| x > 5 }
p pick(2).all? { |x| x > 5 }
p pick(2).none? { |x| x > 9 }
p pick(1).take_while { |x| true }
p pick(2).take_while { |x| x < 5 }
p pick(2).drop_while { |x| x < 5 }
p pick(1).flat_map { |x| [x] }
p pick(2).flat_map { |x| [x, x] }
p pick(1).each_with_index { |x, i| x }
p pick(2).each_with_index { |x, i| x }

