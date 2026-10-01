# The translator that RubyVM::AbstractSyntaxTree uses:
# lib/zr/runtime/lib/zr/ast.rb, over prism. A program that refers to the module
# includes this file before its body and loads the translator with it, so
# Node and Location are complete from the first line, as ruby's are. A
# program that refers to only one of them never parses, and a load that
# waited for a parse would leave it empty. Both files are hidden, so
# Prism and the translator's own constants are not the program's.
require_relative "ast"
