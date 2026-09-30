# `def f(x = nil)` should keep nil observable at the no-arg call
# site, even when other call sites supply a non-nullable scalar
# (symbol / int / float / bool). `f()` gives nil to `x`, not the
# zero value of the other call sites' type, so the `x.nil?` branch
# runs.

def f(x = nil)
  if x.nil?
    "branch: nil"
  else
    "branch: not-nil (#{x.to_s})"
  end
end

puts f()
puts f(:foo)

def g(n = nil)
  n.nil? ? "no-int" : "int=#{n.to_s}"
end

puts g()
puts g(42)
