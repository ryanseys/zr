# A thread that waits for a child parks on the pipe SIGCHLD writes to,
# so its siblings run while the child does: Process.wait, detach, and a
# read on a pipe each let a sleeping thread tick.
ticks = 0
t = Thread.new { 30.times { sleep 0.01; ticks += 1 } }
pid = spawn("sleep 0.25")
Process.wait(pid)
p ticks >= 1 # of 25 that the wait has room for: a busy host runs fewer
t.join
# Long enough that the first join comes before the end, however late.
pid = spawn("sleep 1")
w = Process.detach(pid)
n = 0
until w.join(0.01)
  n += 1
end
p n >= 1, w.value.success?
r, wr = IO.pipe
reader = Thread.new { r.gets }
ticks2 = 0
Thread.new { 5.times { sleep 0.01; ticks2 += 1 }; wr.puts "done" }
p reader.value, ticks2

