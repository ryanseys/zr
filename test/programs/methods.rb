class C
  def f(a, b = 1, *r, c, k:, o: 2, **kw, &blk) = [a, b, r, c, k, o, kw]
  def g = :g
  def h(x) = x * 2
  def self.s = :s
  attr_accessor :at
  private def pv = :pv
  def two((a, b), c) = [a, b, c]
end
module M
  def mm = :mm
end
c = C.new
def c.sing = 1
begin
  c.method(:nope)
rescue NameError => e
  p e
end
begin
  C.instance_method(:nope)
rescue NameError => e
  p e
end
begin
  M.instance_method(:nope)
rescue NameError => e
  p e
end
begin
  C.method(:nope)
rescue NameError => e
  p e
end
p c.method(:f).parameters, c.method(:f).arity, c.method(:g).arity, c.method(:h).arity
p C.instance_method(:f).arity, C.instance_method(:at).parameters, C.instance_method(:at=).parameters, C.instance_method(:at).arity, C.instance_method(:at=).arity
p c.method(:f), c.method(:g), C.instance_method(:h), C.method(:s), c.method(:at=), M.instance_method(:mm), c.method(:pv)
p c.method(:sing)
p c.method(:f).owner, c.method(:f).receiver.equal?(c), c.method(:f).name, C.instance_method(:h).owner, C.instance_method(:h).name
p [].method(:push).parameters, 1.method(:+).parameters, [].method(:each).parameters, [].method(:push), [].method(:push).arity, 1.method(:+).arity
p c.method(:h).source_location, [].method(:push).source_location
p c.method(:h).unbind, C.instance_method(:h).bind(c), C.instance_method(:h).bind_call(c, 5)
p c.method(:h).call(4), c.method(:h).(5), c.method(:h)[6], c.method(:h).to_proc.lambda?, [1, 2].map(&c.method(:h))
p c.method(:h) == c.method(:h), c.method(:h).eql?(c.method(:g)), c.method(:pv).owner, c.method(:h) == C.instance_method(:h)
def top = 1
p method(:top), method(:puts), method(:p).owner
begin
  c.method(:h).call
rescue ArgumentError => e
  p e
end
begin
  c.method(:f).call(1)
rescue ArgumentError => e
  p e
end
p c.method(:f).call(1, 2, 3, 4, k: 5, z: 6)
p C.instance_method(:f).inspect, c.method(:g).unbind.inspect, C.instance_method(:two)
p c.method(:two).call([1, 2], 3), C.instance_method(:two).parameters
o = Object.new
p o.method(:inspect).owner, o.method(:to_s)
begin
  C.instance_method(:mm)
rescue NameError => e
  p e
end
C.include M
p C.instance_method(:mm), c.method(:mm).owner, c.method(:mm)
begin
  C.instance_method(:h).bind(Object.new)
rescue TypeError => e
  p e
end
m = c.method(:h)
def m.extra = 1
p m.call(1)
p c.method(:g).unbind.bind(C.new).call
p c.method(:h).to_proc.call(21), c.method(:h).to_proc.arity
p C.instance_method(:g) == C.instance_method(:g)
p [3, 1].map(&C.instance_method(:h).bind(c))
def raiser(x) = raise("from raiser #{x}")
begin
  method(:raiser).call(1)
rescue => e
  puts e.backtrace
end
begin
  [1].each(&method(:raiser))
rescue => e
  puts e.backtrace
end
