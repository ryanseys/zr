def d(n) = n.is_a?(RubyVM::AbstractSyntaxTree::Node) ? [n.type, *n.children.map { d(it) }] : n
["{**a, **{b: 1}}", "{**a, **{}}"].each { |s| p d(RubyVM::AbstractSyntaxTree.parse(s).children[2]) }
