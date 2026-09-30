iseq = RubyVM::InstructionSequence.of(proc { 1 })
def t(name)
  p [name, yield]
rescue Exception => e
  p [name, e.class, e.message]
end
t(:eval) { iseq.eval }
t(:to_binary) { iseq.to_binary }
top = RubyVM::InstructionSequence.compile("def x; end; proc {}")
t(:top_children) { r = []; top.each_child { |c| r << c.label }; r }
