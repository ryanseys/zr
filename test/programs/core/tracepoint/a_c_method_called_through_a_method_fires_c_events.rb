# A C method that the program calls through a Method or an UnboundMethod
# fires :c_call and :c_return, with its own name and the name of the
# call (an alias), as vm_call0 fires them under Method#call.
obj = Class.new { attr_accessor :x; alias y x; alias y= x= }.new
aw = obj.method(:x=); ar = obj.method(:x); aaw = obj.method(:y=); aar = obj.method(:y)
up = "abc".method(:upcase)
events = []
trace = TracePoint.new(:c_call, :c_return) do |tp|
  next if tp.path != __FILE__
  next if tp.method_id == :call
  events << [tp.event, tp.method_id, tp.callee_id, (tp.return_value if tp.event == :c_return)]
end
body = proc do
  aw.call(1); ar.call; aaw.call(2); aar.call
  up.call
  up.unbind.bind_call("q")
  ar.()
  ar[]
end
body.call
trace.enable(&body)
events.each { p _1 }

# A Struct's accessors too.
s = Struct.new(:x) { alias_method :y, :x; alias_method :y=, :x= }.new(0)
sw = s.method(:y=)
sr = s.method(:x)
events = []
TracePoint.new(:c_call, :c_return) do |tp|
  next if tp.path != __FILE__ || tp.method_id == :call
  events << [tp.event, tp.method_id, tp.callee_id]
end.enable { sw.call(5); sr.call }
events.each { p _1 }
