# InstructionSequence#to_a gives the header of ruby's iseq_data_to_ary and the
# facts of the code: its label, path, first line, type, locals, where it
# is, and the parser that read it.
a = RubyVM::InstructionSequence.compile("")
p a.to_a.first(4), a.to_a[4][:parser], a.to_a[4][:code_location], a.to_a[5..10]
b = RubyVM::InstructionSequence.compile("a = 1\np a", "f.rb", "/x/f.rb", 3).to_a
p b[4].slice(:local_size, :code_location, :parser), b[5..10]
c = RubyVM::InstructionSequence.of(proc { |x| x }).to_a
p c[0], c[9], c[4][:parser]
def m(a) = a
d = RubyVM::InstructionSequence.of(method(:m)).to_a
p d[9], d[5]
