# rubygems puts its own Ruby method in Kernel#require as ruby starts, so
# the instance method is a Ruby method that rubygems wrote. Kernel.require
# stays the C function of the module.
instance = Kernel.instance_method(:require)
single = Kernel.method(:require)

p instance.owner, instance.arity, instance.parameters
p single.owner, single.arity, single.parameters
p single.source_location
p Kernel.private_method_defined?(:require), Kernel.public_method_defined?(:require)
p Kernel.singleton_class.public_method_defined?(:require)
p Kernel.require("set"), require("set")
