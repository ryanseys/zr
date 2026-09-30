File.write("f", "x")
f = File.open("f")
b = +"old"
p f.read(10, b), b
p f.read(10, b), b
b = +"zz"
begin
  f.sysread(3, b)
rescue EOFError => e
  p e.class
end
p b
b = +"zz"
p f.read_nonblock(3, b, exception: false), b
r, w = IO.pipe
w.write("ab")
w.close
b = +"q"
p r.read(5, b), b, r.read(5, b), b
