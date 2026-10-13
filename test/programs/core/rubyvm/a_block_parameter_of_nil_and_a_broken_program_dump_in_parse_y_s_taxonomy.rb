# RubyVM::AbstractSyntaxTree of ruby 4.1's `&nil` block parameter: the ARGS
# node's block child is false, as `**nil` makes its keyword children
# false. An error-tolerant parse of a broken program gives a tree.
def dump(n)
  return n.inspect unless n.is_a?(RubyVM::AbstractSyntaxTree::Node)

  kids = n.children.map { |c| dump(c) }
  "(#{n.type}@#{n.first_lineno}:#{n.first_column}-#{n.last_lineno}:#{n.last_column} #{kids.join(" ")})"
end

[
  "def m(a, &nil); end",
  "def m(&nil) = 1",
  "def m(a, **nil, &nil); end",
  "def m(a, b = 1, *r, k: 2, **o, &nil); end",
  "proc { |a, &nil| }",
  "->(&nil) {}",
  "->() do end",
  "-> () { }",
  "f [->() { }]",
  "def m(&b); end",
].each { |src| puts dump(RubyVM::AbstractSyntaxTree.parse(src)) }

# Broken programs: each parse gives the root type and does not raise.
[
  "def broken(",
  "if true\nelse\n",
  "alias $a $1",
  "alias $a b",
  "a=>{<<b\n",
  "def foo(...); foo 1, ...; end",
  "while x do",
].each do |src|
  p RubyVM::AbstractSyntaxTree.parse(src, error_tolerant: true).type
end
