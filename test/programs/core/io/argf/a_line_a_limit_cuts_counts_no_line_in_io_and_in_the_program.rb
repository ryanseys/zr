# A line that a limit cuts short counts no line, in IO and in the
# program's ARGF; another ARGF counts every piece.
File.write("/tmp/zr_ln", "abc\ndef\nxy")
f = File.open("/tmp/zr_ln")
p [f.gets(2), f.lineno, f.gets(2), f.lineno, f.gets(3), f.lineno, f.gets(5), f.lineno]
f = File.open("/tmp/zr_ln")
p [f.gets(nil, 2), f.lineno, f.gets(nil), f.lineno]
ARGV.replace(["/tmp/zr_ln"])
x = []
ARGF.each_line(2) { x << [_1, ARGF.lineno] }
p x
g = ARGF.class.new("/tmp/zr_ln")
p g.each_line(2).first(3), g.lineno
File.delete("/tmp/zr_ln")
