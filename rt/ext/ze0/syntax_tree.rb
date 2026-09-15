# The translator RubyVM::AbstractSyntaxTree loads on its first parse:
# rt/ext/ze0/ast.rb, over prism. A program that names the module carries
# this file ahead of its body, and the load waits for that first parse,
# so Prism and the translator's own constants are not there before it.
RubyVM::AbstractSyntaxTree.send(:translator=, -> { require_relative "ast" })
