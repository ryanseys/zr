before = Object.constants
require "ripper"
p Object.constants - before
p Ripper.lex("a = 1").size
p defined?(Prism)
p RubyVM::AbstractSyntaxTree.parse("1 + 2").type
p defined?(Prism)
require "prism"
p defined?(Prism), Prism.parse("1").success?
