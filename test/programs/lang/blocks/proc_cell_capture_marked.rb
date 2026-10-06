# A captured Proc lives in a heap cell. GC marks both the cell and the proc,
# so a nested `proc { |v| two.call(v, v) }` keeps working when full cycles are
# frequent. The shape is what matters here.
two = proc { |a, b| [a, b] }
nested = proc { |v| two.call(v, v) }

adder = proc { |a, b| a + b }
twice = proc { |n| adder.call(n, n) }
outer = proc { |n| twice.call(twice.call(n)) }

i = 0
while i < 200
  Array.new(2_000, i * 1.0)      # churn, so the collector actually runs
  GC.start if (i % 50).zero?
  i += 1
end

p nested.call(7)
p outer.call(3)

# the same shape one level deeper, and through a method
def drive(p1, n) = p1.call(n)

deep = proc { |n| nested.call(n) }
p drive(deep, 5)

# a proc captured by a proc captured by a proc
a1 = proc { |x| x * 2 }
a2 = proc { |x| a1.call(x) + 1 }
a3 = proc { |x| a2.call(x) * 10 }
GC.start
GC.start
p a3.call(4)
