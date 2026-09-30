# Array/Comparable conformance
class Ver
  include Comparable
  attr_reader :n
  def initialize(n); @n = n; end
  def <=>(o); n <=> o.n; end
end
p(Ver.new(5).respond_to?(:<))       # Comparable-mixin operators
p(Ver.new(5).respond_to?(:between?))
p([] + [1])                         # empty array literal operand
p([1] + [])
p([] - [1])
p([1, "a", 2] - ["a"])              # different element types
p([1, 2] - [2, "a"])
p([1, 2] & [2, 3])
p([1, 2] | ["a"])
p([].push(1))                       # mutate empty literal directly
p([] << 5)
p([1, 2].unshift(nil))              # unshift nil into a numeric array
p([1.1, 2.2].unshift(nil))
p([1, 2].unshift(nil, nil))
p([1.1, 2.2].include?(2.2))         # Float array include?
p([1.1, 2.2].include?(9.9))
p([].nil?)                          # nil? on an empty array literal
p([].empty?)
