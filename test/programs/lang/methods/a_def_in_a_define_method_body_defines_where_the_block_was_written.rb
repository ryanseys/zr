# A def in a define_method body defines its method on the class where the
# block was written, and super in the body still finds the method.
prc = nil
t = Class.new do
  prc = -> {
    def nested_in_proc
      42
    end
  }
end
c = Class.new { define_method(:test, prc) }
o = c.new
o.test
p o.respond_to?(:nested_in_proc), (t.new.nested_in_proc rescue $!.class)
class K; define_method(:mk) { def inner_k = :k }; end
K.new.mk
p K.new.inner_k
class Base; def hi = :base; end
class Sub < Base; define_method(:hi) { [super(), :sub] }; end
p Sub.new.hi
m = Module.new { define_method(:z) { self.class } }
class UsesM; end
UsesM.include(m)
p UsesM.new.z
c = Class.new { class << self; def foo; end; end }
m = c.method(:foo)
p((Class.new { define_method :bar, m } rescue [$!.class, $!.message]))
p((Class.new { define_method :bar, m.unbind } rescue [$!.class, $!.message]))
class NSMA
  class << self
    undef_method :singleton_method_added
  end
  p((def self.foo; end) rescue [$!.class, $!.message[0, 50]])
end
o = Object.new
class << o
  undef_method :singleton_method_added
  p((def foo; end) rescue [$!.class, $!.message[0, 50]])
  p((define_method(:bar) {}) rescue [$!.class, $!.message[0, 50]])
end
p((o.define_singleton_method(:baz) {}) rescue [$!.class, $!.message[0, 50]])
rec = []
o2 = Object.new
class << o2
  define_method(:method_missing) { |*a| rec << a }
  undef_method :singleton_method_added
  def foo; end
  define_method(:bar) {}
end
o2.define_singleton_method(:baz) {}
p rec
