# The read buffer has a fixed size, set as it is first made: 8192 bytes,
# or the first push back where that is larger. A push back that does
# not fit raises.
r, w = IO.pipe
w.close
s = "a" * 1000
n = 0
begin
  200.times { r.ungetc(s); n += 1 }
rescue IOError => e
  p [n, e.message]
end
p r.read.bytesize

r, w = IO.pipe
w.close
r.ungetc("a" * 70_000)
p r.read.bytesize
r.ungetc("b" * 70_000)
begin
  r.ungetc("c")
  p r.read.bytesize
rescue IOError => e
  p e.message
end

r, w = IO.pipe
w.write("xy")
w.close
p r.getc
r.ungetbyte("q" * 8191)
begin
  r.ungetbyte("z" * 2)
rescue IOError => e
  p e.message
end
p r.read.bytesize
