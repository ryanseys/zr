# Process.detach converts its pid with to_int, keeps it as the thread's
# :pid, and ends with nil when the pid is no child.
t = Process.detach(2**30)
p t.join.value, t[:pid], t.pid
o = Object.new
def o.to_int = 2**30 + 1
p Process.detach(o).join.value
p((Process.detach(Object.new) rescue $!))
