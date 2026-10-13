# A cloned class's methods read the original's constants, as ruby 4.1
# keeps their cref (#21981); a singleton class
# has no copy; a clone keeps the singleton class of its singleton class;
# initialize_dup of a class sees the whole copy; and a bare `private`
# in a method warns.
require "stringio"
class CloneTest
  def foo; TEST; end
end
CloneTest1 = CloneTest.clone
CloneTest2 = CloneTest.clone
class CloneTest1
  TEST = :C1
end
class CloneTest2
  TEST = :C2
end
p [(CloneTest1.new.foo rescue $!), (CloneTest2.new.foo rescue $!)]

c = Class.new
p((c.instance_eval { initialize_copy(1) } rescue $!.class))
o = Object.new
sc = class << o; self; end
p((sc.dup rescue $!.class))
p((BasicObject.dup rescue $!.class))

def capture
  $stderr = StringIO.new
  yield
  $stderr.string.sub(/\A.*?: /, "")
ensure
  $stderr = STDERR
end
p(capture { Class.new { def self.foo = private; foo } })
p(capture { Class.new { def self.foo = protected; foo } })
p(capture { Class.new { class << self; alias priv private; end; def self.foo = priv; foo } })

klass = Class.new { def self.bar = :bar }
o = klass.new
o.singleton_class.singleton_class.define_method(:s2_method) { :s2 }
clone = o.clone
p [o.singleton_class.instance_methods(false), clone.singleton_class.instance_methods(false)]
p [(o.singleton_class.s2_method rescue $!.class), (clone.singleton_class.s2_method rescue $!.class)]
p [o.singleton_class.singleton_class.instance_methods(false), clone.singleton_class.singleton_class.instance_methods(false)]

ancestors = sc_ancestors = nil
b = Class.new
b.define_singleton_method(:initialize_dup) do |x|
  ancestors = self.ancestors
  sc_ancestors = singleton_class.ancestors
  super(x)
end
a = Class.new(b)
c = a.dup
p ancestors == [c, b, *Object.ancestors], sc_ancestors == [c.singleton_class, b.singleton_class, *Object.singleton_class.ancestors]
p c.ancestors == [c, b, *Object.ancestors], c.singleton_class.ancestors == [c.singleton_class, b.singleton_class, *Object.singleton_class.ancestors]
