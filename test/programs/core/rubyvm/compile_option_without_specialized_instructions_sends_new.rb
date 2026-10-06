# RubyVM::InstructionSequence.compile_option= keeps the options it is
# given. With specialized instructions off, an eval compiles `new` as a
# send of Class#new, so a trace sees its c-call, as without opt_new.
# The build fires trace events, as the program names TracePoint.
TracePoint.new(:line) {}
class Foo; def initialize(a = 1) = (@a = a); end
I = RubyVM::InstructionSequence
d = I.compile_option
I.compile_option = { specialized_instruction: false }
p I.compile_option[:specialized_instruction], I.compile_option[:peephole_optimization]
I.compile_option = { peephole_optimization: false, foo: 1, debug_level: 2 }
p I.compile_option.values_at(:specialized_instruction, :peephole_optimization, :debug_level), I.compile_option.key?(:foo)
I.compile_option = nil
p I.compile_option[:debug_level]
ev = []
eval <<~RUBY, nil, "traced"
  set_trace_func(proc { |e, f, l, m, b, k| ev << [e, l, m, k] if f == "traced" })
  Foo.new
  Foo.new(2) { }
  set_trace_func(nil)
RUBY
ev.each { p _1 }
I.compile_option = d
p I.compile_option == d
ev = []
eval <<~RUBY, nil, "traced"
  set_trace_func(proc { |e, f, l, m, b, k| ev << [e, l, m, k] if f == "traced" })
  Foo.new
  set_trace_func(nil)
RUBY
ev.each { p _1 }
I.compile_option = false
p I.compile_option
I.compile_option = true
p I.compile_option
begin
  I.compile_option = 3
rescue TypeError => e
  p e
end
