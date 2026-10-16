# RubyVM::InstructionSequence#trace_points of compiled code: the opening
# event on the first line, each :line event, and the closing event on the
# last line.
def foo(x)
  a = 1
  [a].each do |y|
    y
  end
  b = 2 if x
  while b && b > 3
    b -= 1
  end
  b
end

def bar = :bar

pr = proc { |z|
  z
}

lam = lambda do
  1
  2
end

class Body
  X = 1
  def self.made = X
end

iseq = RubyVM::InstructionSequence
p iseq.of(method(:foo)).trace_points
p iseq.of(method(:bar)).trace_points
p iseq.of(pr).trace_points
p iseq.of(lam).trace_points
p iseq.of(Body.method(:made)).trace_points
p iseq.compile("a = 1\nb = 2\n").trace_points
