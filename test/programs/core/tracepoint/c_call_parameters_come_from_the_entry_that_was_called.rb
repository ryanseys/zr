# A c_call's parameters come from the method entry that was called: an
# alias still gives them after its original name is removed.
klass = Class.new do
  attr_writer :bar
  alias_method :set_bar, :bar=
  remove_method :bar=
  attr_reader :baz
  alias_method :get_baz, :baz
end
obj = klass.new
got = []
TracePoint.new(:c_call, :c_return) { |tp| got << [tp.event, tp.method_id, tp.callee_id, tp.parameters] }.enable do
  obj.set_bar(1)
  obj.get_baz
  obj.baz
end
got.each { p it }
got.clear
TracePoint.new(:c_call) { |tp| got << [tp.method_id, tp.parameters] }.enable { "a".upcase; 1 + 2; [].push(1) }
got.each { p it }
