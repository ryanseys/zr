# enum_inject takes up to two arguments, and none only with a block, so
# its arity message says 0..2 with a block and 1..2 without one.
class Three
  include Enumerable

  def each
    yield 1
    yield 2
    yield 3
  end
end

def show
  p yield
rescue ArgumentError, TypeError => e
  p [e.class, e.message]
end

[[1, 2, 3], (1..3), Three.new, { a: 1, b: 2 }].each do |list|
  show { list.inject }
  show { list.inject(1, 2, 3) }
  show { list.inject(1, 2, 3) { |a, b| a } }
  show { list.reduce }
  show { list.reduce(1, :+, 3) { |a, b| a } }
  show { list.reduce(1, :+, 3, 4) }
end

show { [1, 2, 3].inject(:+) }
show { [1, 2, 3].inject(10, :+) }
show { [1, 2, 3].inject(10) { |a, b| a * b } }
show { [1, 2, 3].inject { |a, b| a - b } }
show { [1, 2, 3].inject("+") }
show { [1, 2, 3].inject(0, "*") }
show { [1, 2, 3].inject(1) }
show { [1, 2, 3].inject(0, 1) }
show { [].inject(:+) }
show { [].inject(5, :+) }
show { (1..4).reduce(:*) }
show { Three.new.reduce(2) { |a, b| a + b } }
