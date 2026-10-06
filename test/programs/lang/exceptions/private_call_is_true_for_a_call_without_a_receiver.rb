begin
  foo(1)
rescue NoMethodError => e
  p e.private_call?
end
begin
  self.foo(1)
rescue NoMethodError => e
  p e.private_call?
end
def m = baz(1)
begin
  m
rescue NoMethodError => e
  p e.private_call?
end
o = Object.new
begin
  o.instance_eval { qux(1) }
rescue NoMethodError => e
  p e.private_call?
end
x = proc { foo(1) }
begin
  x.call
rescue NoMethodError => e
  p e.private_call?
end
B = Class.new(BasicObject)
def t(label)
  yield
rescue NoMethodError => e
  p [label, e.private_call?]
end
t(:basic_fcall) { B.new.instance_eval { foo(1) } }
t(:basic_fcall0) { B.new.instance_eval { foo() } }
t(:basic_call) { B.new.foo(1) }
class B
  def run = foo(2)
  def run_self = self.foo(3)
end
t(:basic_in_method) { B.new.run }
t(:basic_self) { B.new.run_self }

class A
  def foo = super
end
t(:super) { A.new.foo }
o = Object.new
def o.method_missing(*) = super
t(:mm_fcall) { o.instance_eval { zz(1) } }
t(:mm_call) { o.zz(1) }
t(:send) { o.send(:zz) }
t(:public_send) { o.public_send(:zz) }
t(:__send__) { o.__send__(:zz, 1) }
t(:direct_method_missing) { o.method_missing(:zz) }
t(:integer_self) { 1.instance_eval { yy(1) } }
t(:safe_nav) { o&.zz }
t(:op_assign) { o.zz += 1 }
t(:index) { o[1] }
t(:attr_set) { o.zz = 1 }
t(:self_attr_set) { o.instance_eval { self.zz = 1 } }
begin
  o.instance_eval { zz }
rescue NameError => e
  p [e.class, e.respond_to?(:private_call?)]
end

# A direct call of method_missing reports the kind of the last miss.
begin
  o.method_missing(:qq)
rescue NameError => e
  p [e.class, e.name]
end
