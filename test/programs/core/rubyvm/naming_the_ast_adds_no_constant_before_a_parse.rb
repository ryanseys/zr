# A program that names RubyVM::AbstractSyntaxTree finds Node and Location
# there, and no constant of the parser under the module until a parse.
p Object.constants.include?(:Prism), defined?(Prism)
p RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree::Location
node = RubyVM::AbstractSyntaxTree.parse("1 + 2")
p node.is_a?(RubyVM::AbstractSyntaxTree::Node), node.type
p node.children.last.type

