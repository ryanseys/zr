# frozen_string_literal: true

# A `(a, b)` parameter takes ONE slot like any other, and the names
# inside it are written from that slot afterwards, by ruby's own
# destructure -- the same split a multiple assignment uses. ruby reports
# such a parameter with no name at all.

p [[1, 2], [3, 4]].map { |(a, b)| a + b }
p({ a: 1, b: 2 }.each_with_index.map { |(k, v), i| [k, v, i] })
p proc { |(a, (b, c))| [a, b, c] }.call([1, [2, 3]])
p proc { |(a, *r)| [a, r] }.call([1, 2, 3])
p proc { |(a, *)| a }.call([1, 2, 3])
p proc { |(a, b), (c, d)| [a, b, c, d] }.call([1, 2], [3, 4])

p lambda { |(k, v), i| [k, v, i] }.parameters
p proc { |(k, v), i| }.parameters

def pair((a, b), c) = [a, b, c]
p pair([1, 2], 3)
p method(:pair).parameters
p method(:pair).arity

# A value that is not an Array goes through ruby's `to_ary` rule, and one
# that answers none binds the whole value to the first name.
p proc { |(a, b)| [a, b] }.call(7)

class Pairy
  def to_ary = [:x, :y]
end
p proc { |(a, b)| [a, b] }.call(Pairy.new)
__END__
[3, 7]
[[:a, 1, 0], [:b, 2, 1]]
[1, 2, 3]
[1, [2, 3]]
1
[1, 2, 3, 4]
[[:req], [:req, :i]]
[[:opt], [:opt, :i]]
[1, 2, 3]
[[:req], [:req, :c]]
2
[7, nil]
[:x, :y]
