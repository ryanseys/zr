# While a read waits to fill a String, ruby locks it (rb_str_locktmp): a
# change to it from another thread raises. zr has no lock on a String,
# so the change goes through.
r, w = IO.pipe
buf = " " * 10
th = Thread.new { r.sysread(10, buf) }
Thread.pass until th.stop?
begin
  buf.replace("")
  p :changed
rescue RuntimeError => e
  p e.message
end
w.write("a" * 10)
p th.value.bytesize
