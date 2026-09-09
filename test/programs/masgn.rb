a, b = 1, 2
p [a, b]
a, b = b, a
p [a, b]
a, b, c = [1, 2]
p [a, b, c]
a, *b = 1, 2, 3
p [a, b]
*a, b = 1, 2, 3
p [a, b]
a, (b, c), d = 1, [2, 3], 4
p [a, b, c, d]
a, b = 5
p [a, b]
a, b = nil
p [a, b]
x = (a, b = 7, 8)
p x
a, = [9, 10]
p a
a, b, *c, d = 1, 2, 3, 4, 5, 6
p [a, b, c, d]
class Pt
  attr_reader :x, :y
  def set
    @x, @y = 1, 2
    self
  end
end
q = Pt.new.set
p [q.x, q.y]
[[1, [2, 3]], [4, [5, 6]]].each { |a, (b, c)| p [a, b, c] }
{ k: [1, 2] }.each { |key, (a, b)| p [key, a, b] }
[[1, 2], [3, 4]].each_with_index { |(a, b), i| p [a, b, i] }
def two = [1, 2]
a, b = two
p [a, b]
class Pair
  def to_ary = [:l, :r]
end
a, b = Pair.new
p [a, b]
a, b = *[1, 2], 3
p [a, b]
first, *rest = "just one"
p [first, rest]
h = {}
h[:x], h[:y] = 1, 2
p h
a, * = 1, 2, 3
p a
