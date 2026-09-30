# Multi-argument `yield` in a method body. A yield with fewer arguments
# than the block has parameters sets the rest to nil.

# 1. Basic 2-arg yield.
def add_pair
  yield 1, 2
end

add_pair { |a, b| puts a + b }

# 2. 3-arg yield with block returning to a local.
def sum_triple
  yield 10, 20, 30
end

sum_triple { |a, b, c| puts a + b + c }

# 3. Mixed-arity yields in the same method. The smaller yields
#    must not leak values from the larger ones: the second yield's `b`
#    is nil, not 999. `b.to_i` turns nil into 0.
def mixed_yield
  yield 100, 999
  yield 200
end

total = 0
mixed_yield { |a, b| total = total + a + b.to_i }
puts total

# 4. Multi-arg yield from a class instance method.
class Dispatcher
  def emit
    yield 100, 200
    yield 300, 400
  end
end

Dispatcher.new.emit { |x, y| puts x + y }

# 5. Three different yield arities in one method. The smaller yields
#    give nil for the missing block params, and `b.to_i` / `c.to_i`
#    turn nil into 0.
def varied
  yield 1, 2, 3
  yield 10, 20
  yield 100
end

acc = 0
varied { |a, b, c| acc = acc + a + b.to_i + c.to_i }
puts acc
