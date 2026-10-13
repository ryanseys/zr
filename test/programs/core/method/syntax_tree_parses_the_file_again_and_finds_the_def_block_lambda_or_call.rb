# ruby 4.1's #syntax_tree: Method, UnboundMethod, Proc and
# Thread::Backtrace::Location give the Ruby::Prism node of their code, from
# a parse of the file again. A def gives its DefNode, a lambda its
# LambdaNode, a block (a define_method body too) the call it is for, and a
# location the node that its frame runs. Code that is not from a file, a C
# or attribute method, and a file that changed since it was compiled give
# nil.
require "tmpdir"

def show(label)
  node = yield
  p [label, node.is_a?(Ruby::Prism::Node) ? [node.class, node.type, node.slice, node.start_line, node.start_column] : node]
rescue => e
  p [label, e.class, e.message]
end

def plain(a) = a + 1
def multi(x,
          y)
  x + y
end
class C
  attr_reader :r
  def inst = :i
  def self.sing = :s
  define_method(:dm) { |q| q }
  define_method(:dm_m, instance_method(:inst))
  alias al inst
  S = Struct.new(:a)
end
def return_block(&b) = b
body = return_block { 42 }
C.define_method(:dm_p, &body)
pr = proc { |x| x * 2 }
pr2 = proc do |z|
  z
end
la = ->(y) { y }
la2 = lambda { 3 }
nested = proc { proc { :inner } }.call
def where = caller_locations(1, 1).first
loc = where
loc2 = [1].map { where }.first
show(:plain) { method(:plain).syntax_tree }
show(:multi) { method(:multi).syntax_tree }
show(:inst) { C.instance_method(:inst).syntax_tree }
show(:sing) { C.method(:sing).syntax_tree }
show(:dm) { C.instance_method(:dm).syntax_tree }
show(:dm_m) { C.instance_method(:dm_m).syntax_tree }
show(:dm_p) { C.instance_method(:dm_p).syntax_tree }
show(:alias) { C.instance_method(:al).syntax_tree }
show(:attr) { C.instance_method(:r).syntax_tree }
show(:struct) { C::S.instance_method(:a).syntax_tree }
show(:proc) { pr.syntax_tree }
show(:proc_do) { pr2.syntax_tree }
show(:lambda) { la.syntax_tree }
show(:lambda_kw) { la2.syntax_tree }
show(:nested) { nested.syntax_tree }
show(:c_method) { method(:puts).syntax_tree }
show(:symbol_proc) { :upcase.to_proc.syntax_tree }
show(:method_proc) { method(:plain).to_proc.syntax_tree }
show(:location) { loc.syntax_tree }
show(:location_block) { loc2.syntax_tree }
show(:eval_proc) { eval("proc { 1 }").syntax_tree }
show(:eval_def) { eval("def ev = 1"); method(:ev).syntax_tree }
show(:iseq) { RubyVM::InstructionSequence.of(pr).syntax_tree.type }
show(:node_type) { method(:plain).syntax_tree.is_a?(Ruby::Prism::Node) }

Dir.mktmpdir do |dir|
  path = File.join(dir, "target.rb")
  File.write(path, "def t_method = :ok\nT_PROC = proc { :ok }\ndef t_loc = caller_locations(0, 1).first\ndef t_data = :ok\n__END__\noriginal\n")
  load path
  show(:loaded) { method(:t_method).syntax_tree }
  show(:loaded_proc) { T_PROC.syntax_tree }
  show(:loaded_loc) { t_loc.syntax_tree }
  show(:loaded_range) { t_loc.source_range.then { |r| [r.start_line, r.start_column, r.end_line, r.end_column] } }
  File.write(path, File.read(path).sub("original", "changed"))
  show(:data_changed) { method(:t_data).syntax_tree }
  File.write(path, "def t_method = :changed\n")
  show(:changed) { method(:t_method).syntax_tree }
  File.write(path, "def t_method = (\n")
  show(:broken) { method(:t_method).syntax_tree }
  File.delete(path)
  show(:deleted) { method(:t_method).syntax_tree }
end
