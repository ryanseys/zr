# A block that runs as a define_method method reports that method in its
# events, also when it raises; a def written inside it reports the def.
def go
  ev = []
  cap = proc { |tp| ev << [tp.event, tp.method_id, tp.callee_id] }
  o = Class.new { define_method(:m) { raise }; alias alias_m m }.new
  TracePoint.new(:b_return, :return, &cap).enable { o.alias_m rescue nil }
  p ev[0..1]; ev.clear
  o = Class.new { define_method(:m) { tap { return } }; alias alias_m m }.new
  TracePoint.new(:b_return, &cap).enable { o.alias_m }
  p ev; ev.clear
  o = Class.new { define_method(:m) { [1].each { |x| x } }; alias alias_m m }.new
  TracePoint.new(:b_return, :line, &cap).enable { o.alias_m }
  p ev; ev.clear
  o = Class.new { define_method(:m) { def inner = 1; inner } }.new
  TracePoint.new(:call, :return, &cap).enable { o.m }
  p ev
end
go
pr = proc { |x| x }
o = Class.new { define_method(:pm, &pr) }.new
ev = []
TracePoint.new(:b_call, :b_return, :call, :return) { |tp| ev << [tp.event, tp.method_id] }.enable { o.pm(1); pr.call(2) }
p ev
