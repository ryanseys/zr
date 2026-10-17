# ruby compiles a file before it runs, so a file that turns off CRuby's
# specialized instructions keeps its own inline `new` (opt_new), and a
# TracePoint hears no Class#new in it. zr compiles every file of the
# program before any runs, so when one file turns them off, `new` is a
# send of Class#new in all of them.
RubyVM::InstructionSequence.compile_option = { specialized_instruction: false }
events = []
TracePoint.new(:c_call) { events << it.method_id if it.method_id == :new }.enable { Object.new }
p events
