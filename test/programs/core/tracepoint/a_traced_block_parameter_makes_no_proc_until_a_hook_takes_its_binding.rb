# A traced &b parameter that the method only calls makes no Proc, as an
# untraced one; a hook that takes the frame's Binding gets the block as a
# Proc that outlives the call.
def cl(&b) = b.call(1)
def counted
  c = {}
  cl { }
  ObjectSpace.count_objects(c)
  n = c[:T_DATA]
  cl { }
  ObjectSpace.count_objects(c)
  c[:T_DATA] - n
end
GC.disable
p counted
kept = nil
tp = TracePoint.new(:return) { |t| kept = t.binding if t.method_id == :cl }
x = 10
tp.enable { cl { |v| v + x } }
GC.enable
GC.start
b = kept.local_variable_get(:b)
p b.class, b.call(5), b.lambda?
seen = []
TracePoint.new(:call) { |t| seen << t.binding.local_variables if t.method_id == :cl }.enable { cl { } }
p seen
