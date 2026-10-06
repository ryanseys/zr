# IO.pipe makes both ends non-blocking, but a child that takes one as a
# standard stream gets it blocking, as ruby gives it: a `cat` that reads
# before the parent writes waits for the bytes and does not fail with
# EAGAIN. The flag is on the open file, so the parent's end blocks too.
r, w = IO.pipe
pid = spawn("cat", in: r)
r.close
sleep 0.3
w.puts "late"
w.close
Process.wait(pid)
p $?.success?

r, w = IO.pipe
out_r, out_w = IO.pipe
pid = spawn("cat", in: r, out: out_w)
out_w.close
p out_r.nonblock? if out_r.respond_to?(:nonblock?)
w.puts "through"
w.close
Process.wait(pid)
p out_r.read
