# `public :foo` in a subclass makes no copy of the ancestor's method: the
# entry calls whatever the search above the class finds at each call.
def try = yield rescue "#{$!.class}: #{$!.message}"

class A
  private

  def foo(arg = nil) = 1
end

class B < A
  public :foo
end

u = B.instance_method(:foo)
p u == B.public_instance_method(:foo)
p u.owner, u.parameters, u.inspect.sub(/ \S+:\d+>/, ">")

A.remove_method(:foo)
b = B.new
p u.parameters, u.bind_call(b)
p B.instance_methods(false), B.public_instance_methods(false), B.private_instance_methods(false)
p b.respond_to?(:foo), B.method_defined?(:foo), B.public_method_defined?(:foo)
p try { B.instance_method(:foo) }
p try { b.method(:foo) }
p try { b.foo }
p try { b.send(:foo) }
p try { b.public_send(:foo) }

class A
  def foo = :back
end
p b.foo, b.respond_to?(:foo), B.instance_method(:foo).owner

class A
  private def foo = :private_again
end
p b.foo

class B
  remove_method :foo
end
p try { b.foo }

# A method taken before its class defines the name again keeps its body,
# and its `super` still starts above that body's own class.
class C0
  def foo = [:foo]
end

class C1 < C0
  def foo = super + [:bar]
end
m1 = C1.instance_method(:foo)

class C2 < C1
  private :foo
end
p C2.private_instance_methods(false)
m2 = C2.instance_method(:foo)

class C1
  remove_method :foo
  def foo = [:bar2]
end
m3 = C2.instance_method(:foo)
c = C2.new
p m1.bind_call(c), m1.owner
p m2.bind_call(c), m2.owner
p m3.bind_call(c), m3.owner
p c.send(:foo)

# With the method in between removed, the copy finds the one above it.
class D0
  def foo(a = nil, b = nil) = 0
end

class D1 < D0
  private

  def foo(a = nil) = 1
end

class D2 < D1
  public :foo
end
u = D2.instance_method(:foo)
p u.super_method == D0.instance_method(:foo)
D1.remove_method(:foo)
p u.parameters, u.super_method == D0.instance_method(:foo), u.bind_call(D2.new)
p D2.instance_method(:foo).owner, D2.new.foo

# super_method stops at a copy with nothing above it.
e1 = Class.new { private def foo; end }
e2 = Class.new(e1) { public :foo }
e3 = Class.new(e2) { def foo; end }
e1.class_eval { undef foo }
p e3.instance_method(:foo).super_method
