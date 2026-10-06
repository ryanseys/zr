# An Enumerable method that the program calls sends `each` as
# rb_block_call does: a C `each` fires :c_call and :c_return, with the
# name of the alias the class gave it.
o = Class.new(String) { include Enumerable; alias each each_char }.new("foo")
events = []
TracePoint.new(:c_call, :c_return) { |tp| events << [tp.event, tp.method_id, tp.callee_id] if tp.path == __FILE__ }.enable do
  o.find { true }
  (1..2).map { _1 }
  {a: 1}.min_by { _2 }
  [3, 1].sort_by { -_1 }
end
events.each { p _1 }

k = Class.new { alias_method :alias_raise, :raise; def m = alias_raise }.new
events = []
TracePoint.new(:c_return) { |tp| events << [tp.event, tp.method_id, tp.callee_id] }.enable { k.m rescue nil }
p events[0]
