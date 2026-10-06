# Method, UnboundMethod and Proc: inspect of a metaclass method, repeated
# underscore parameters, super_method of an alias, and curry bindings.
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
show(1) { String.method(:include).inspect }
m = Module.new { def bar = 1 }
o = Object.new
o.extend(m)
o.singleton_class
show(2) { o.method(:bar).inspect.sub(/0x\h+/, "X").sub(/ \S+:\d+$/, "") }
show(3) { (method(:puts) << method(:p)).lambda? }
show(4) { (method(:puts) >> method(:p)).lambda? }
def under(_, _) = 1
show(5) { method(:under).parameters }
show(6) { proc { |_, _| }.parameters }
mm = Class.new { def method_missing(n, *) = n; def respond_to_missing?(*) = true }.new
show(7) { mm.method(:zz) == mm.method(:zz) }
show(8) { mm.method(:zz).eql?(mm.method(:zz)) }
A = Class.new { def foo = :a }
B = Class.new(A) { def foo = :b; private :foo; public :foo }
show(9) { B.new.method(:foo).super_method&.owner }
C = Class.new(A) { alias_method :bar, :foo }
show(10) { C.new.method(:bar).super_method }
show(11) { Class.new(A) { def foo = :c; alias_method :foo2, :foo }.new.method(:foo2).super_method.owner }
show(12) { Class.method(:new).unbind == Class.instance_method(:new) }
cn = Class.new { class << self; alias_method :n, :new; end }
show(14) { proc { |a, b| }.curry.binding }
module Mo; def foo_super = (defined?(super) ? super : :none); end
class Par; def foo_super = :parent; end
