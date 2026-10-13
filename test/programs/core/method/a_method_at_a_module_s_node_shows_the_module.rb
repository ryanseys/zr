# A Method whose class is a module's node shows the module: super_method
# of a module's method, and bind of a module's method, also to an object
# that does not include the module (ruby #22321). A singleton method
# found through an extended module shows the class past the modules.
def show(m) = m.inspect.gsub(/0x\h+/, "").sub(/ \S+:\d+>/, ">")
M = Module.new { def foo = 1; def bar = 2 }
N = Module.new { def foo = super + 1 }
class P; def foo = 0; end
class C < P; include M; include N; def foo = super; end
o = C.new
p show(o.method(:foo)), show(o.method(:foo).super_method), show(o.method(:foo).super_method.super_method), show(o.method(:foo).super_method.super_method.super_method)
p show(o.method(:bar)), show(o.method(:bar).unbind), show(o.method(:bar).unbind.bind(o))
p show(M.instance_method(:bar).bind(o)), show(M.instance_method(:bar).bind(Object.new)), show(M.instance_method(:bar).bind_call(o).class)
p M.instance_method(:bar).bind(Object.new).call, show(M.instance_method(:foo).bind(o).super_method)
p show(C.instance_method(:bar)), show(C.instance_method(:bar).bind(o)), show(C.instance_method(:foo).bind(o).super_method)
s = Object.new; s.extend(M)
p show(s.method(:bar)), show(s.method(:bar).unbind.bind(s)), show(s.singleton_class.instance_method(:bar).bind(s))
p show(1.method(:then).unbind.bind(2)), show(Kernel.instance_method(:then).bind(3))
# A class's prepended module and the class's own method.
Pre = Module.new { def baz = super }
class D; prepend Pre; def baz = 3; end
d = D.new
p show(d.method(:baz)), show(d.method(:baz).super_method), show(D.instance_method(:baz).bind(d))
p d.method(:baz).super_method.call, M.instance_method(:bar).bind(o).call
