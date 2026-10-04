# A TracePoint that only eval code names sees the calls of the program's
# own methods. zr arms trace events only for code that names TracePoint,
# not for a name in a string, so this needs `zr run --trace` (or
# ZR_TRACE=1); without it, the TracePoint warns and sees no calls.

def double(x) = x * 2

calls = []
point = eval("TracePoint.new(:call, :return) { |tp| calls << [tp.event, tp.method_id] }")
point.enable { double(21) }
p calls
