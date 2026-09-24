# The translator RubyVM::AbstractSyntaxTree stands on: rt/ext/zr/ast.rb,
# over prism. A program that names the module carries this file ahead of
# its body and loads the translator with it, so Node and Location answer
# whole from the first line, as ruby's do -- a program that only names
# one of them never parses, and a load that waited for a parse would
# leave it empty. Both files are hidden, so Prism and the translator's
# own constants are not the program's.
require_relative "ast"
