# A def whose first decision is pure is answered at the site on that
# arm: a recursion's leaves, a guard clause, operands past the fixnums,
# a redefined operator, a redefined def, and a receiver of another class.
def fib(n)
  if n < 2
    n
  else
    fib(n - 1) + fib(n - 2)
  end
end
def tak(x, y, z) = y < x ? tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y)) : z
def guarded(a, b)
  return a if a == b
  return :nil_b if b.nil?
  [a, b].max
end
def deep(n) = n == 0 ? :bottom : deep(n - 1)
p fib(20), tak(12, 6, 0), tak(1, 2, 2**70), tak(2**70, 2**71, 3), guarded(2**70, 2**70)
p fib(1.5), fib(0.5), fib(-3)
p guarded(1, 1), guarded(1, nil), guarded(3, 4), guarded(:x, :x), guarded("a", "a".dup)
p deep(5000)
begin
  deep(10_000_000)
rescue SystemStackError => e
  p e.class
end
class Integer
  alias_method :lt, :<
  def <(other) = lt(other)
end
p fib(15)
class Integer
  def <(other) = true
end
p fib(10)
class Integer
  alias_method :<, :lt
end
def fib(n) = n < 2 ? :leaf : [fib(n - 1), fib(n - 2)].size
p fib(5)
class Other
  def fib(n) = :other
  def go = fib(1)
end
p Other.new.go, send(:fib, 1)
