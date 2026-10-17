klass = Class.new { def initialize(x = 0) = @x = x }
events = []
trace = TracePoint.new(:c_call, :c_return) do
  events << [it.event, it.method_id, it.lineno, (it.return_value.class.name if it.event == :c_return)] if it.method_id == :new
end
trace.enable do
  p Set.new == Set.new([0])
  Object.new
  klass.new(1)
  klass.new { :ignored }
end
events.each { p it }
p RubyVM::InstructionSequence.compile_option[:specialized_instruction]
