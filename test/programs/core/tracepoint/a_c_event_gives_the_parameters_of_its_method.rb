# The parameters of a :c_call or a :c_return are those its method's
# arity gives, as rb_unnamed_parameters makes them.
seen = []
TracePoint.new(:c_call, :c_return) { |tp| seen << [tp.event, tp.method_id, tp.parameters] if %i[getbyte each_char size insert fetch puts format sub].include?(tp.method_id) }.enable do
  "ab".getbyte(0); "ab".each_char { }; [1].size; "a".insert(0, "b"); { a: 1 }.fetch(:a); format("%d", 1); "a".sub("a") { "b" }
end
seen.each { p _1 }
