# The compiler that a program carries for eval requires digest, and it
# must not give the program digest's Object#Digest, or etc's IO#pathconf,
# until the program requires them itself.
x = RubyVM::AbstractSyntaxTree
eval("1")
p Object.private_method_defined?(:Digest), respond_to?(:Digest, true), IO.method_defined?(:pathconf)
require "digest"
p Object.private_instance_methods(false).include?(:Digest), Digest(:SHA256)
p eval("[1, 2].sum"), RubyVM::AbstractSyntaxTree.parse("1 + 2").type
