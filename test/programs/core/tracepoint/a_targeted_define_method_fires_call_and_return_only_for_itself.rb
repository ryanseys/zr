# A TracePoint aimed at a define_method's Method gets that method's call and
# return only; the block it shares with another method fires for both.
blk = Proc.new {}
o = Object.new
o.define_singleton_method(:one, &blk)
o.define_singleton_method(:two, &blk)
ev = []
tp = TracePoint.new(:call, :return, :b_call, :b_return) { |t| ev << [t.event, t.method_id] }
tp.enable(target: o.method(:one)) { o.one; o.two }
p ev
ev.clear
tp.enable(target: o.method(:two)) { o.one; o.two }
p ev
def m = [1].each { |x| x }
class Object
  alias m2 m
end
ev.clear
TracePoint.new(:call, :return) { |t| ev << [t.event, t.method_id, t.callee_id] }.enable(target: method(:m)) { m; m2 }
p ev
