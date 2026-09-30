# A zero limit reads nothing and counts no line; a negative limit is no
# limit. Each of each_line, readlines and foreach names itself when it
# refuses a zero limit.
path = "/tmp/zr_spec_limits.txt"
File.write(path, "ab\ncd\n")
File.open(path) do |f|
  p f.gets(0), $_, f.lineno, f.gets(-5), f.lineno
  p((f.each_line(0) {} rescue $!), (f.readlines(0) rescue $!))
  f.rewind
  p f.readlines(-2), f.each_line(0), f.each(1)
end
p((IO.foreach(path, 0) {} rescue $!), (IO.readlines(path, 0) rescue $!))
r, w = IO.pipe
w.write("ab\n")
w.close
p r.gets(0), r.gets(-1), r.gets(0)
File.delete(path)
