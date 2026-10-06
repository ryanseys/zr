# The method lists of an object read a singleton class's own methods,
# and the class's, from where a prepended module moved them. A
# singleton class lists none of the methods of its class's singleton.
o = Object.new
def o.foo = nil
p o.methods(false)
class << o; prepend Module.new; end
p o.methods(false)
p o.singleton_methods(false)

c = Class.new(Module) { private def foo = nil }
k = c.new
k.singleton_class
c.module_eval { prepend(Module.new) }
p k.private_methods(false)

d = Class.new
def d.foo = nil
p d.singleton_methods(false)
p d.singleton_class.singleton_methods(false)
s = d.new.singleton_class
p s.singleton_methods - [:yaml_tag]
p s.singleton_methods(false)
