# A thread that waits for a child parks on the pipe SIGCHLD writes to,
# so its siblings run while the child does: Process.wait, detach, and a
# read on a pipe each let a sleeping thread tick.
ticks = 0
t = Thread.new { 30.times { sleep 0.01; ticks += 1 } }
pid = spawn("sleep 0.25")
Process.wait(pid)
p ticks >= 10
t.join
pid = spawn("sleep 0.2")
w = Process.detach(pid)
n = 0
until w.join(0.01)
  n += 1
end
p n >= 5, w.value.success?
r, wr = IO.pipe
reader = Thread.new { r.gets }
ticks2 = 0
Thread.new { 5.times { sleep 0.01; ticks2 += 1 }; wr.puts "done" }
p reader.value, ticks2

__END__
true
true
true
"done\n"
5
