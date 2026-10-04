# A TracePoint that only eval code names sees the calls of the program's
# own methods.

def double(x) = x * 2

calls = []
point = eval("TracePoint.new(:call, :return) { |tp| calls << [tp.event, tp.method_id] }")
point.enable { double(21) }
p calls
