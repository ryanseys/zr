# RubyVM::AbstractSyntaxTree over prism with parse.y taxonomy: the tree
# shapes below are the oracle's own dumps (type, location, children) for the
# tier of constructs zr maps faithfully. node_id values are zr-numbered
# (prism's ids are parse-internal), so only their presence is pinned.
$stderr.reopen(IO::NULL)

def dump(n)
  return "nil" if n.nil?
  unless n.is_a?(RubyVM::AbstractSyntaxTree::Node)
    return n.inspect
  end
  kids = n.children.map { |c| dump(c) }
  "(#{n.type} [#{n.first_lineno}:#{n.first_column}-#{n.last_lineno}:#{n.last_column}] #{kids.join(' ')})"
end

[
  "1",
  "1 + 2",
  "x = 5",
  "x = 5; x",
  "puts \"hi\"",
  "foo",
  "a.b",
  "def m(a, b = 1) a end",
  "if x then 1 else 2 end",
  "[1, :two, \"three\"]",
  "{ a: 1 }",
  "C = 1",
  "while true do break end",
  "a { |x| x }",
  "1..2",
  "class Foo; end",
  "return 1 if false",
  "@iv = 1",
  "nil",
  "true or false",
].each do |src|
  ast = RubyVM::AbstractSyntaxTree.parse(src)
  puts "#{src.inspect} => #{dump(ast)}"
end

