# Threads that wait for children at the same time: each gets its own
# child and status, in whatever order the children end.
def child(code)
  r, w = IO.pipe
  pid = fork { w.close; r.read; exit!(code) }
  r.close
  [pid, w]
end

kids = [3, 4, 5].map { |code| child(code) }
waiters = kids.map { |pid, _| Thread.new { Process.waitpid2(pid) } }
Thread.pass until waiters.all?(&:stop?)
kids.reverse_each { |_, w| w.close }
waiters.zip(kids).each do |t, (pid, _)|
  got, status = t.value
  p [got == pid, status.exitstatus]
end

# A waiter that is killed while it waits leaves the others waiting.
(pid_a, w_a), (pid_b, w_b) = child(1), child(2)
a = Thread.new { Process.wait(pid_a) }
b = Thread.new { Process.wait(pid_b); $?.exitstatus }
Thread.pass until a.stop? && b.stop?
a.kill
a.join
p a.status
w_b.close
p b.value
w_a.close
p Process.wait2(pid_a).last.exitstatus

# WNOHANG among parked waiters returns nil while the child runs.
pid, w = child(7)
t = Thread.new { Process.wait2(pid).last.exitstatus }
Thread.pass until t.stop?
p Process.waitpid(pid, Process::WNOHANG)
w.close
p t.value

# With no children left, a waiter gets ECHILD.
p(begin
  Thread.new { Thread.current.report_on_exception = false; Process.wait }.value
rescue Errno::ECHILD => e
  e.class
end)
