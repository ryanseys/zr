# A forked child of a parent that runs threads preempts a thread that
# computes without a call, so another thread still runs.
Thread.new { sleep }
r, w = IO.pipe
pid = fork do
  r.close
  q = Thread::Queue.new
  busy = Thread.new { i = 0; i += 1 while q.empty?; i }
  other = Thread.new { q << true; :ran }
  w.puts [other.value, busy.value.positive?].inspect
end
w.close
puts r.gets
Process.wait(pid)
p $?.success?
