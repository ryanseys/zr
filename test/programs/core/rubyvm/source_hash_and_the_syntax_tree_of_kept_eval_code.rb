# ISeq#source_hash is the 64-bit FNV-1a hash of the source up to its
# __END__ line, also in to_a's misc, and the same for every iseq of one
# file. With RubyVM.keep_script_lines, code that an eval compiled gives its
# syntax_tree; without it, nil. A file that changed or broke gives nil.
def try(l) = (p [l, yield]) rescue p([l, $!.class, $!.message])
try(:no_keep) { [eval("proc { :ok }").syntax_tree, eval("def nk = 1; method(:nk)").syntax_tree] }
RubyVM.keep_script_lines = true
eval("def ksl = :ok\nKSL = proc { :ok }\n", binding, "(eval-ksl)", 1)
try(:m) { method(:ksl).syntax_tree&.type }
try(:pr) { KSL.syntax_tree&.type }
try(:m_range) { method(:ksl).source_range }
iseq = RubyVM::InstructionSequence.compile("x = 1")
try(:hash) { [iseq.source_hash.class, iseq.source_hash.size, iseq.source_hash == RubyVM::InstructionSequence.compile("x = 1").source_hash, iseq.source_hash == RubyVM::InstructionSequence.compile("x = 2").source_hash] }
try(:to_a) { iseq.to_a[4][:source_hash] == iseq.source_hash }
require "tmpdir"
Dir.mktmpdir do |dir|
  path = File.join(dir, "t.rb")
  File.write(path, "def pt = :ok\n")
  load path
  try(:file) { method(:pt).syntax_tree.type }
  File.write(path, "def pt = :changed\n")
  try(:changed) { method(:pt).syntax_tree }
  File.write(path, "def pt = (\n")
  try(:broken) { method(:pt).syntax_tree }
  File.delete(path)
  try(:gone) { method(:pt).syntax_tree }
end
i = RubyVM::InstructionSequence.compile("x = 1\n__END__\nabc")
p i.source_hash, i.to_a[4].keys.first(5)
def mm = 1
p RubyVM::InstructionSequence.of(method(:mm)).source_hash == RubyVM::InstructionSequence.compile_file(__FILE__).source_hash
p RubyVM::InstructionSequence.compile("").source_hash
try(:line) { eval("

def third = 3", binding, "(e3)", 7); method(:third).syntax_tree.then { [_1.type, _1.location.start_line] } }
