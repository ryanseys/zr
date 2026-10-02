# Closing an IO wakes each other thread that waits on it with IOError,
# as ruby's rb_notify_fd_close does: a reader of a socket or a pipe, and
# a writer parked on a full pipe.
require "socket"
Thread.report_on_exception = false

def parked(t) = (Thread.pass while t.status == "run")

srv = TCPServer.new("127.0.0.1", 0)
3.times do
  a = TCPSocket.new("127.0.0.1", srv.addr[1])
  b = srv.accept
  t = Thread.new do
    loop { b.readpartial(10) }
  rescue IOError => e
    e.message
  end
  parked(t)
  b.close
  p t.value
  a.close
end
srv.close

r, w = IO.pipe
t = Thread.new { r.gets }
parked(t)
r.close
begin
  t.value
rescue IOError => e
  p e.message
end
w.close

r, w = IO.pipe
t = Thread.new do
  w.write("x" * 1_000_000)
rescue IOError => e
  e.message
end
parked(t)
w.close
p t.value
r.close
