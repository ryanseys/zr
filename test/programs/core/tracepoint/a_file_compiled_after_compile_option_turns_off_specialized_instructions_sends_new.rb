# With CRuby's specialized instructions off, `new` in a file compiled
# after it is a send of Class#new, so a TracePoint hears its :c_call and
# :c_return (power_assert shows the value of each `new` this way).
RubyVM::InstructionSequence.compile_option = { specialized_instruction: false }
require_relative "plain_new/news"
