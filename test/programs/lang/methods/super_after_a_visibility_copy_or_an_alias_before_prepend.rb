# super from a method reached through a module's private(:name) copy
# goes on in the receiver's own ancestors, and an alias made before a
# prepend skips the prepended module.
def t(l)
  p [l, yield]
rescue StandardError => e
  p [l, e.class, e.message[0, 70]]
end
class Object
  def bar = "Object#bar"
end
module M1
  def bar = super
end
module M2
  include M1
  private(:bar)
  def foo = bar
end
extend M2
t(:private_extended) { foo }
o = Object.new
o.extend(M2)
t(:private_extended_obj) { o.foo }
class Host; include M2; end
t(:private_included) { Host.new.foo }

pm = Module.new { def m = "P" + super }
a = Class.new { def m = "A" }
b = Class.new(a) do
  def m = "B" + super
  alias_method :m2, :m
  prepend pm
  alias_method :m3, :m
end
t(:alias_before) { b.new.m2 }
t(:alias_after) { b.new.m3 }
