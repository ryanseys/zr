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

# ---- InstructionSequence.
iseq = RubyVM::InstructionSequence.compile("40 + 2")
p iseq.class
p iseq.eval
p [iseq.label, iseq.base_label, iseq.path, iseq.absolute_path, iseq.first_lineno]
p iseq.inspect
p [iseq.script_lines, iseq.trace_points]
p RubyVM::InstructionSequence.compile_option.class
begin
  RubyVM::InstructionSequence.load_from_binary("x")
rescue RuntimeError => e
  p [e.class, e.message]
end
begin
  RubyVM::InstructionSequence.compile("def broken(")
rescue SyntaxError => e
  p e.class
end
p RubyVM::InstructionSequence.compile("1", "myfile.rb").path
p RubyVM::InstructionSequence.compile("1", "myfile.rb", "/abs/myfile.rb", 7).first_lineno
p RubyVM::InstructionSequence.new("2 * 3").eval
File.write("/tmp/zr_ast_fixture.rb", "z = 42\n")
f = RubyVM::InstructionSequence.compile_file("/tmp/zr_ast_fixture.rb")
p [f.label, f.path]
p f.eval
