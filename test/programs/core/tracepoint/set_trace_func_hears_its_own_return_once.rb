# set_trace_func's hook hears the c-return of the call that set it, once,
# whether or not something else traced at that call: another thread's
# hook or an enabled TracePoint.
def record
  events = []
  set_trace_func(proc { |ev, file, line, mid| events << [ev, line, mid] if file == __FILE__ })
  y = 2 + 2
  set_trace_func(nil)
  events
end

p record

q = Thread::Queue.new
t = Thread.new { Thread.current.add_trace_func proc { |*| }; q.pop }
Thread.pass until t.stop?
p record
q << 1
t.join

tp = TracePoint.new(:line) {}
tp.enable
p record
tp.disable

# A thread's own hooks stop when it ends.
seen = []
t = Thread.new { Thread.current.add_trace_func proc { |ev, file, line| seen << [ev, line] if file == __FILE__ }; :ok }
p t.value
n = seen.size
x = 1 + 1
p seen.size == n, record
