# Stress test: a lambda goes through a chain of 5 top-level methods. Each
# method passes its `g` to the next one, and only f1 calls `g.call`.

def f1(g)
  g.call(1)
end

def f2(g)
  f1(g)
end

def f3(g)
  f2(g)
end

def f4(g)
  f3(g)
end

def f5(g)
  f4(g)
end

double = ->(x) { x * 2 }
puts f5(double)
puts f4(double)
puts f3(double)
puts f2(double)
puts f1(double)
