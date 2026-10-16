# RubyVM::InstructionSequence#node_id: the id of the code's node in the
# parse of its file, for a method, a block, a lambda and a compiled
# string; to_a keeps it among its facts.
def m(a)
  a + 1
end

def endless = :e

pr = proc { 2 }
lam = -> { 3 }

class K
  def self.s = 4
end

iseq = RubyVM::InstructionSequence
[method(:m), method(:endless), pr, lam, K.method(:s)].each do |body|
  code = iseq.of(body)
  p [code.label, code.node_id, code.to_a[4][:node_id] == code.node_id]
end
compiled = iseq.compile("x = 1\nx + 2\n")
p [compiled.node_id.class, compiled.to_a[4][:node_id] == compiled.node_id]
p iseq.instance_method(:node_id).arity
