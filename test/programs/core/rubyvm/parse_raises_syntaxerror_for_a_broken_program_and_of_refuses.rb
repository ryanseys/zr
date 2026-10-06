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

# ---- errors and options.
begin
  RubyVM::AbstractSyntaxTree.parse("def broken(")
rescue SyntaxError => e
  p e.class
end
p RubyVM::AbstractSyntaxTree.parse("def broken(", error_tolerant: true).type
begin
  RubyVM::AbstractSyntaxTree.of(proc { 1 })
rescue RuntimeError => e
  p [e.class, e.message]
end
p RubyVM::AbstractSyntaxTree.of(method(:puts))
File.write("/tmp/zr_ast_fixture.rb", "z = 42\n")
pf = RubyVM::AbstractSyntaxTree.parse_file("/tmp/zr_ast_fixture.rb")
p [pf.type, pf.children.last.type]

