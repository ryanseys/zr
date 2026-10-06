# TracePoint sees the evaluated code, and nothing of the compiler.
calls = []
tp = TracePoint.new(:call, :c_call) { |t| calls << t.method_id }
tp.enable
x = eval("1 + 2")
tp.disable
p x, calls
