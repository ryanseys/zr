# CRuby's external `next` runs `each` in a fiber, each_with_index sends
# `each` by name, and a lazy chain runs through Generator and Yielder,
# and TracePoint hears each of those calls. zr's `next` walks with no
# event, each_with_index walks an Array without sending `each`, and its
# lazy stages are classes of its own, which TracePoint shows.
def trace(label)
  events = []
  tp = TracePoint.new(:c_call) { |t| events << "#{t.defined_class}##{t.method_id}" }
  result = tp.enable { yield }
  puts "#{label}: #{events.join(" ")} => #{result.inspect}"
end

trace(:enum_next) { [1, 2].each_slice(1).next }
trace(:with_index) { %w[a b].each_with_index.map { |s, i| s * (i + 1) } }
trace(:lazy) { [1, 2, 3].lazy.map { _1 * 2 }.first(2) }
