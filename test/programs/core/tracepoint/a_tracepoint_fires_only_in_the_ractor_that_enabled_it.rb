# A TracePoint's hook belongs to the Ractor that enabled it: the events
# of another Ractor's code do not reach it, with or without a target.
def work = :done

main_calls = []
outer = TracePoint.new(:call) { |tp| main_calls << tp.method_id }
outer.enable

r = Ractor.new do
  calls = []
  inner = TracePoint.new(:call) { |tp| calls << tp.method_id }
  inner.enable
  work
  Ractor.main << :enabled
  Ractor.receive
  work
  inner.disable
  calls
end

Ractor.receive
work
r << :go
inner_calls = r.value
outer.disable
p main_calls.count(:work)
p inner_calls.count(:work)

# A targeted point is Ractor-local too.
counts = 3.times.map do
  Ractor.new do
    seen = 0
    tp = TracePoint.new(:call) { seen += 1 }
    tp.enable(target: Object.instance_method(:work)) { 2.times { work } }
    seen
  end
end.map(&:value)
p counts

# A point that the main Ractor enabled with a block hears nothing from a
# Ractor that runs inside the block.
heard = []
TracePoint.new(:call) { |tp| heard << tp.method_id }.enable do
  Ractor.new { work }.value
end
p heard.count(:work)

# set_trace_func is Ractor-local as well.
events = []
set_trace_func(proc { |event, _file, _line, id, *| events << id if event == "call" })
Ractor.new { work }.value
work
set_trace_func(nil)
p events.count(:work)
