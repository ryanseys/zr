# An attribute has no ISEQ, so RubyVM::AbstractSyntaxTree.of returns nil for
# it, as for a builtin; a body written in Ruby refuses, as CRuby refuses an
# ISEQ that prism compiled (test_ast.rb's test_of_c_method).
c = Class.new { attr_reader :foo; attr_writer :bar; def baz = 1; define_method(:qux) { 2 } }
p RubyVM::AbstractSyntaxTree.of(c.instance_method(:foo)), RubyVM::AbstractSyntaxTree.of(c.instance_method(:bar=))
p RubyVM::InstructionSequence.of(c.instance_method(:foo))
[c.instance_method(:baz), c.instance_method(:qux), proc { 1 }, method(:puts)].each do |body|
  p RubyVM::AbstractSyntaxTree.of(body)
rescue RuntimeError => e
  p e.message
end
