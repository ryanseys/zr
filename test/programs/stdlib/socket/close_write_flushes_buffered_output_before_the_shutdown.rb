# close_write on a socket, or on a plain IO for a socket's descriptor,
# flushes the buffered output before it shuts the write side down (ruby
# 4.1, #18900): the peer gets the bytes, and a later close does not fail.
require "socket"
a, b = UNIXSocket.pair
a.sync = false
a.write("buffered")
p a.close_write
p b.read(8)
p (a.close; :closed)
p b.read
b.close

a, b = UNIXSocket.pair
a.sync = false
a.write("x")
p a.close_write
p a.close_write
begin
  a.write("y")
rescue IOError => e
  p [e.class, e.message]
end
p b.read
a.close
b.close

# IO#close_write on a plain IO for a socket's descriptor.
a, b = UNIXSocket.pair
io = IO.for_fd(a.fileno, "r+", autoclose: false)
io.sync = false
io.write("plain")
begin
  p io.close_write
  p b.read(5)
rescue => e
  p [e.class, e.message]
end
io.close rescue p $!
a.close
b.close

# A write-only IO on a socket's descriptor closes after the shutdown.
a, b = UNIXSocket.pair
w = IO.for_fd(a.fileno, "w", autoclose: false)
w.sync = false
w.write("wo")
p w.close_write
p w.closed?
p b.read(2)
a.close
b.close

# A pipe's read end still refuses close_write.
r, w = IO.pipe
begin
  r.close_write
rescue IOError => e
  p [e.class, e.message]
end
p w.close_write
p w.closed?
r.close
