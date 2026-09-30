# An eval compiles its string here with a compiler in Ruby, over prism,
# which the program carries. Its constants, Zr and Prism, stay out of
# the program's sight, as ruby has neither: not in Object.constants, not
# for defined?, const_get or a string an eval runs, nor after
# RubyVM::AbstractSyntaxTree's translator loads.
eval "1"
p Object.constants.include?(:Prism), defined?(Prism)
p Object.constants.include?(:Zr), defined?(Zr)

p Object.const_defined?(:Prism), (Object.const_get(:Prism) rescue $!.class), Module.constants.include?(:Prism)
p eval("defined?(Prism)"), eval("1 + 2")
p RubyVM::AbstractSyntaxTree.parse("1").type, defined?(Prism), defined?(Zr)

