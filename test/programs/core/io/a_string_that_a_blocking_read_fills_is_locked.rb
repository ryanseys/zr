# While a read waits to fill a String, the String is locked
# (rb_str_locktmp_ensure): a change to it from another thread raises.
# After the read, the String can change again.
def try = yield rescue "#{$!.class}: #{$!.message}"

%i[sysread readpartial read].each do |m|
  r, w = IO.pipe
  buf = +" " * 10
  th = Thread.new { r.public_send(m, 10, buf) }
  Thread.pass until th.stop?
  p [m, try { buf.replace("") }, try { buf << "x" }, buf.bytesize]
  w.write("a" * 10)
  p th.value.bytesize, buf.frozen?, try { buf << "y"; buf.bytesize }
end

# A frozen buffer is refused before the read.
r, w = IO.pipe
w.write("abc")
p try { r.readpartial(3, "x".freeze) }, try { r.sysread(3, "x".freeze) }
w.close
p r.readpartial(3, +""), try { r.read(3, +"z") }
