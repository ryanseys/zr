# `obj.singleton_methods` finds a `def obj.x`, and the singleton CLASS
# must report it too: `instance_methods(false)`, `public_instance_methods(false)`,
# `method_defined?`, and `instance_method` must all agree with
# `singleton_methods`.
#
# A CLASS's singleton (`def K.cm`) must report the same way, since a
# class method is stored class-keyed to begin with.

o = Object.new
def o.hi = 1

p o.singleton_methods
p o.singleton_class.instance_methods(false)
p o.singleton_class.public_instance_methods(false)
p o.singleton_class.method_defined?(:hi)
p o.singleton_class.instance_method(:hi).owner == o.singleton_class

class K; end
def K.cm = 2
p K.singleton_class.instance_methods(false)
p K.singleton_methods
