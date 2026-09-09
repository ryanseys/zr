# native only: fibers switch stacks with a raw function
f = Fiber.new do |a, b|
  p [:start, a, b]
  x = Fiber.yield(a + b)
  p [:got, x]
  y, z = Fiber.yield
  p [:got2, y, z]
  :done
end
p f.alive?
p f.resume(1, 2)
p f.resume(:x)
p f.resume(7, 8)
p f.alive?
begin
  f.resume
rescue FiberError => e
  p e
end
begin
  Fiber.yield
rescue FiberError => e
  p e
end
g = Fiber.new { raise ArgumentError, "inside" }
begin
  g.resume
rescue => e
  p e, e.backtrace.size
end
p g.alive?
gen = Fiber.new do
  3.times { |i| Fiber.yield(i * 10) }
  nil
end
4.times { p gen.resume }
h = Fiber.new { Fiber.yield 1; Fiber.yield 2; 3 }
p h.resume, h.resume, h.resume
nested = Fiber.new do
  inner = Fiber.new { Fiber.yield :inner1; :inner_done }
  a = inner.resume
  b = Fiber.yield [:outer, a]
  [b, inner.resume, inner.alive?]
end
p nested.resume
p nested.resume(:back)
p Fiber.current.class, Fiber.current.alive?
c = Fiber.new { Fiber.current }
p c.resume.equal?(c)
d = Fiber.new { d.resume }
begin
  d.resume
rescue FiberError => e
  p e
end
strings = Fiber.new do
  s = +""
  10.times { |i| s << i.to_s; GC.start; Fiber.yield(s.dup) }
end
5.times { strings.resume }
GC.start
p strings.resume
lj = Fiber.new { [1, 2].each { |v| Fiber.yield v }; :after }
p lj.resume, lj.resume, lj.resume, lj.alive?
def deep(n) = n == 0 ? Fiber.yield(:deep) : deep(n - 1)
dd = Fiber.new { deep(200); :out }
p dd.resume, dd.resume
