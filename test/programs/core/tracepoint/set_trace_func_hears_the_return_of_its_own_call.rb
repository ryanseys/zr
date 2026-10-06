# A hook that set_trace_func, Thread#set_trace_func or add_trace_func
# sets hears the c-return of the call that set it first, at that call's
# line, with no binding. It runs untraced, and may remove itself there.
set_trace_func(proc { |*a| p [a[0], File.basename(a[1]), a[2], a[3], a[4].class, a[5]]; set_trace_func(nil) if a[0] == "c-return" })
t = Thread.current
r = []
t.set_trace_func(proc { |*a| r << [a[0], a[2], a[3], a[4].class, a[5]] })
t.set_trace_func(nil)
p r
r.clear
t.add_trace_func(proc { |*a| r << [a[0], a[2], a[3], a[5]] })
t.set_trace_func(nil)
p r
# A hook set on another thread hears nothing of this one.
other = Thread.new { sleep }
Thread.pass until other.stop?
s = []
other.set_trace_func(proc { |*a| s << a[0] })
p s
other.set_trace_func(nil)
other.kill.join
# nil sets no hook and hears nothing.
p set_trace_func(nil)
