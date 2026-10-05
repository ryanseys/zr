# A lambda's :b_call and :b_return give its parameters as a lambda's,
# and a proc's as a proc's.
f = -> x, y, z { }
g = proc { |a, b| }
h = lambda { |q, r = 1, *s| }
rows = []
TracePoint.new(:b_call, :b_return) { |tp| rows << [tp.event, tp.parameters] }.enable do
  f.call(1, 2, 3)
  g.call(1, 2)
  h.call(1)
end
rows.each { |row| p row }
