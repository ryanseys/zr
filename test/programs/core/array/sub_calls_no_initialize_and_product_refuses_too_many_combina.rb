# `Sub[...]` makes the subclass's instance with neither its initialize
# nor its replace called. product counts its result first: too many is
# a RangeError, and a block gets each combination as it is made.
class Pair < Array
  def initialize(a, b) = raise("initialize")
  def replace(*) = raise("replace")
end
p [Pair[5, 6], Pair[5, 6].class]
a = (0..100).to_a
begin
  a.product(a, a, a, a, a, a, a, a, a, a)
rescue RangeError => e
  p e.message
end
p a.product(a, a, a, a, a, a, a, a, a, a) { |c| break c.sum }
p [1, 2].product([3, 4], [5]), [1].product([]), [1].product([]) { raise }
