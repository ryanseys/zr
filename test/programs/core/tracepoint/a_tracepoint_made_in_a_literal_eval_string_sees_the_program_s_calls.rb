# A TracePoint that only a literal eval string names sees the calls of
# the program's own methods: the build reads the string's code as it
# reads the file's (eval, the *_eval forms, Binding#eval and
# RubyVM::InstructionSequence.compile).
def double(x) = x * 2

calls = []
point = eval("TracePoint.new(:call, :return) { |tp| calls << [tp.event, tp.method_id] }")
point.enable { double(21) }
p calls

class Box
  def open = :open
end
lines = []
point = Box.class_eval("TracePoint.new(:call) { |tp| lines << tp.method_id }")
point.enable { Box.new.open }
p lines

seen = []
point = binding.eval("TracePoint.new(:return) { |tp| seen << [tp.method_id, tp.return_value] }")
point.enable { double(2) }
p seen

compiled = RubyVM::InstructionSequence.compile("TracePoint.new(:call) { |tp| $called = tp.method_id }").eval
compiled.enable { double(1) }
p $called
