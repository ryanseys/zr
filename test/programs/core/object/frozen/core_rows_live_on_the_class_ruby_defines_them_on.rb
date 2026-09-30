# CRuby writes some rows on a class of its own even where they share the
# function Kernel's row uses: `===` on nil, true, false and Symbol,
# `freeze` on String, Array, Hash and Module, `dup` and `clone` on Proc
# and the method classes. Main owns `using` and `ruby2_keywords`. Equal
# methods share a hash, also through an alias of one C function.

p singleton_class.private_instance_methods(false).sort
p Kernel.private_instance_methods.include?(:using)
def a(*args) = args
ruby2_keywords :a
p a(k: 1).last

[NilClass, TrueClass, FalseClass, Symbol].each { |c| p [c, c.instance_method(:===).owner] }
[String, Array, Hash, Module].each { |c| p [c, c.instance_method(:freeze).owner] }
[Proc, Method, UnboundMethod].each { |c| p [c, c.instance_method(:dup).owner, c.instance_method(:clone).owner] }
p String.instance_method(:dup).owner, Module.instance_method(:==).owner

pr = proc { 1 }.freeze
p pr.clone.frozen?, pr.dup.frozen?
p nil === nil, true === true, :a === :a, false === nil, Module == Module

um = String.instance_method(:size)
p um.hash == String.instance_method(:size).hash
p um.hash == String.instance_method(:length).hash
p "a".method(:upcase).unbind.hash == String.instance_method(:upcase).hash
p "a".method(:upcase).hash == "a".method(:upcase).hash

