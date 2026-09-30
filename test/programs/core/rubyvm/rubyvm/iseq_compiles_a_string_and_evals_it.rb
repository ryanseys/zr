# RubyVM::InstructionSequence.compile takes a string of Ruby, which eval
# runs at the top level, under main; a string that does not parse raises
# SyntaxError as it compiles.
i = RubyVM::InstructionSequence.compile("1 + 2")
p i, i.label, i.base_label, i.path, i.absolute_path, i.first_lineno, i.eval
j = RubyVM::InstructionSequence.compile("x = 40; x + 2", "f.rb", "/abs/f.rb", 3)
p j, j.path, j.absolute_path, j.first_lineno, j.eval, j.eval
p RubyVM::InstructionSequence.compile("self").eval
begin
  RubyVM::InstructionSequence.compile("1 +")
rescue SyntaxError => e
  p e.class
end
begin
  RubyVM::InstructionSequence.compile("raise 'q'").eval
rescue => e
  p e.message, e.backtrace.first
end
RubyVM::InstructionSequence.compile("def from_iseq = :defined").eval
p from_iseq
p RubyVM::InstructionSequence.of(proc {}).inspect.sub(/@.*:/, "@FILE:")

