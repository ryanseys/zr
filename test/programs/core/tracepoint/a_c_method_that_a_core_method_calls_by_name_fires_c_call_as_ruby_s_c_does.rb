# TracePoint hears a C method that a core method calls by name, as
# CRuby's C does through rb_funcall, rb_block_call and rb_check_funcall:
# a Symbol block's send, each_slice's size check, join's to_s. Where CRuby's C takes a path with no call
# (inject of an operator over an Array), nothing fires.
def trace(label)
  events = []
  tp = TracePoint.new(:c_call) { |t| events << "#{t.defined_class}##{t.method_id}" }
  tp.enable { yield }
  puts "#{label}: #{events.join(" ")}"
end
trace(:map_sym) { %w[a b].map(&:upcase) }
trace(:sort_sym) { [[2, 1]].map(&:sort) }
trace(:each_slice) { [1, 2].each_slice(1) { } }
trace(:sort_by) { [3, 1].sort_by { _1 } }
trace(:inject_sym) { [1, 2].inject(:+) }
trace(:sum) { [1, 2].sum }
trace(:min_by) { [1, 2].min_by { _1 } }
trace(:hash_each) { {a: 1}.each { } }
trace(:struct_new) { Struct.new(:a).new(1) }
trace(:puts_obj) { o = Object.new; def o.to_s = "o"; $stdout.write(""); "#{o}" }
trace(:array_join) { [1, :a].join(",") }
trace(:uniq) { [1, 1].uniq }
trace(:max) { [1, 2].max }
trace(:group_by_sym) { %w[a bb].group_by(&:size) }
trace(:inject_block) { [1, 2].inject { _1 + _2 } }
trace(:inject_range) { (1..3).inject(:+) }
trace(:join_nested) { [1, [2, :b]].join("-") }
