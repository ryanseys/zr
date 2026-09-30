# A parameter that is BOTH captured by an escaping block AND reassigned
# has one variable. The block sees the last value that the method gives
# it. The timeout gem uses this shape with a captured `message ||= ...`.

def f(x)
  t = proc { x }
  x = 2
  t.call
end
p f(1)
def g(m = nil)
  m ||= "d"
  t = proc { m }
  t.call
end
p g
p g("y")
