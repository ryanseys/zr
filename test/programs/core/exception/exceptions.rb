e = (raise "boom" rescue $!)
p e.full_message(highlight: false), e.full_message(highlight: false, order: :top)
class E < StandardError; def initialize(msg = "default E") = super; end
p E.new.message, E.exception.message, E.exception("x").message, E.new("y").exception("z").message
x = E.new("q")
p x.exception.equal?(x), x.exception("q").equal?(x), x.exception("r").equal?(x), x.exception("r").class
p e == e, e == RuntimeError.new("boom")
n = (foo rescue $!)
p n.name, n.receiver.class, n.class
n = (Object.new.foo rescue $!)
p n.name, n.args, n.private_call?
k = ({ a: 1 }.fetch(:b) rescue $!)
p k.key, k.receiver, k.message
f = ("a".freeze << "b" rescue $!)
p f.receiver, f.message
begin
  raise "a"
rescue => a
  begin
    raise "b"
  rescue => b
    p b.cause.message, a.cause
  end
end
begin
  raise TypeError, "t", cause: nil
rescue => c
  p c.cause
end
begin
  raise "z", cause: 3
rescue TypeError => c
  p c.message
end
begin
  raise
rescue => c
  p c.class, c.message
end
begin
  raise 3
rescue TypeError => c
  p c.message
end
begin
  raise RuntimeError, "m", ["x:1", "y:2"]
rescue => c
  p c.backtrace
end
c = RuntimeError.new("m")
c.set_backtrace("one")
p c.backtrace, c.backtrace_locations
p StandardError.new.message, StandardError.new(nil).message, StandardError.new(3).message, Exception.new("x").inspect, Exception.new("").inspect, Exception.new("a\nb").inspect
p UncaughtThrowError.superclass, UncaughtThrowError.new(:zz, 5).tag, UncaughtThrowError.new(:zz, 5).value
p SystemExit.new.status, SystemExit.new(3).status, SystemExit.new(false).status, SystemExit.new(2, "bye").message, SystemExit.new.message, SystemExit.new.success?
p RuntimeError.new("").detailed_message, RuntimeError.new("a\nb").detailed_message, RuntimeError.new.detailed_message, RuntimeError.new(3).message
class Custom < StandardError; def to_s = "custom"; end
p Custom.new("q").message, Custom.new.detailed_message, Custom.new.inspect
class E2 < StandardError; def initialize(m) = raise("inner"); end
begin
  raise E2, "x"
rescue => e
  puts e.backtrace
end
begin
  E2.new("z")
rescue => e
  puts e.backtrace
end
class F < StandardError; def exception(m = nil) = raise("in exception"); end
begin
  raise F.new
rescue => e
  puts e.backtrace
end
p LoadError.ancestors.first(3), StopIteration.superclass, FloatDomainError.superclass, NotImplementedError.new("x").message
begin
  raise NotImplementedError
rescue ScriptError => e
  p e.class, e.message
end
begin
  raise Interrupt
rescue Exception => e
  p e.class, e.message
end
d = E.new("orig")
d2 = d.dup
p d2.message, d2.class, d2.equal?(d)
s = "abc"
t = s.dup
t << "d"
p s, t, s.frozen?, "x".freeze.dup.frozen?, "x".freeze.clone.frozen?, "x".freeze.clone(freeze: false).frozen?, "x".clone(freeze: true).frozen?
a = [1, [2]]
b = a.dup
b << 3
b[1] << 4
p a, b
h = { k: [1] }
h2 = h.dup
h2[:z] = 1
p h, h2
class Pt
  attr_accessor :x
  def initialize(x) = @x = x
  def initialize_copy(o)
    @x = o.x + 100
    super
  end
end
pt = Pt.new(1)
def pt.solo = :solo
p pt.dup.x, pt.clone.x, pt.clone.solo, (pt.dup.solo rescue $!.class), pt.dup.singleton_methods, pt.clone.singleton_methods
p 1.dup, :s.clone, nil.dup, (1.clone(freeze: false) rescue $!)
begin
  Pt.new(1).send(:initialize_copy, "str")
rescue TypeError => e
  p e
end
