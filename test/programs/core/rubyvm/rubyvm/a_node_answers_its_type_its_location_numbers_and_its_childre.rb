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

# ---- the Node surface.
ast = RubyVM::AbstractSyntaxTree.parse("x = 1 + 2\ny = x", keep_script_lines: true)
p ast.class
p ast.type
p [ast.first_lineno, ast.first_column, ast.last_lineno, ast.last_column]
p ast.node_id.is_a?(Integer)
p ast.children.last.type
p ast.script_lines
p ast.source
p ast.children.last.source
p ast.inspect
p ast.locations.map(&:class)
p ast.locations.first.inspect
p [ast.locations.first.first_lineno, ast.locations.first.last_column]
plain = RubyVM::AbstractSyntaxTree.parse("x=1")
p [plain.script_lines, plain.source, plain.tokens, plain.all_tokens]

