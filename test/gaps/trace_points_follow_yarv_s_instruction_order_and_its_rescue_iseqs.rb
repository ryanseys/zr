# ruby lists an instruction sequence's events in the order of its YARV
# instructions, with a :return for each `leave`, and a rescue clause is
# an instruction sequence of its own. zr compiles to machine code and lists
# the events in the order of the source, once each, with the rescue
# clause's lines in the method's own list.
def cased(b)
  case b
  when 2 then :two
  else :other
  end
end

def guarded
  :body
rescue ArgumentError
  :rescued
ensure
  :ensured
end

p RubyVM::InstructionSequence.of(method(:cased)).trace_points
p RubyVM::InstructionSequence.of(method(:guarded)).trace_points
