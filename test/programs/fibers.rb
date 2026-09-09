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
root = Fiber.current
a = Fiber.new { |x| p [:a, x]; y = root.transfer(:from_a); p [:a_back, y]; :a_done }
p a.transfer(1)
p a.transfer(2)
p a.alive?
p((a.transfer rescue $!))
b = Fiber.new { p :b; (Fiber.yield rescue p $!); :b_end }
p b.transfer
p((b.resume rescue $!))
c = Fiber.new { Fiber.yield 1; 2 }
p c.resume
p((c.transfer rescue $!))
d = Fiber.new { root.transfer(:d1); Fiber.yield(:d2) rescue p $!; :d3 }
p d.transfer
p((d.resume rescue $!))
p d.transfer
e = Fiber.new { f = Fiber.new { root.transfer(:in_f) }; f.resume; :e_end }
e = Fiber.new { f = Fiber.new { (root.transfer(:in_f) rescue p $!); :f_end }; p f.resume; :e_end }
p e.resume
g = Fiber.new { h = Fiber.new { Fiber.current.transfer(:self) }; p h.resume; :g_end }
p g.resume
p Fiber.current.transfer(9)
k = Fiber.new { root.transfer(:k1); :k_end }
p k.transfer
m = Fiber.new { k.transfer; :m_end }
p m.transfer
p m.alive?, k.alive?
n = Fiber.new { raise "boom" }
p((n.transfer rescue $!))
q = Fiber.new { root.transfer(:q1); q2 = Fiber.new { Fiber.yield :inner; :inner_end }; p q2.resume; p q2.resume; :q_end }
p q.transfer
p q.transfer
r = Fiber.new { :r_end }
p r.transfer(1, 2)
s = Fiber.new { |*a| a }
p s.transfer(1, 2), s.alive?
t = Fiber.new { root.transfer }
p t.transfer(1, 2)
t2 = Fiber.new { p Fiber.current == t2; root.transfer(:x1); :t2_end }
p t2.transfer
p t2.transfer(:v)
