# Bytes written while a stream was not sync, and still in its buffer when
# it turns sync, go out with the next write; a close in sync mode drops
# them (ruby 4.1, #18902), and so does the end of the program.
p(IO.pipe { |r, w| w.sync = false; w.write("buffered"); w.sync = true; w.close; r.read })
p(IO.pipe { |r, w| w.sync = false; w.write("data"); w.close; r.read })
p(IO.pipe { |r, w| w.sync = true; w.write("sync"); w.close; r.read })
p(IO.pipe { |r, w| w.sync = false; w.write("a"); w.sync = true; p((r.read_nonblock(5) rescue $!.class)); w.write("b"); p r.read_nonblock(5); w.close; r.read })
p(IO.pipe { |r, w| w.sync = false; w.write("a"); w.sync = true; w.print("b", "c"); w.puts("d"); w.close; r.read })
p(IO.pipe { |r, w| w.sync = false; w.write("a"); w.sync = true; w.flush; w.close; r.read })
p(IO.pipe { |r, w| w.sync = false; w.write("a"); w.sync = true; w.sync = false; w.close; r.read })
p(IO.pipe { |r, w| w.sync = false; w.write("a"); w.sync = true; w << "b"; w.close; r.read })
# Several parts in one sync write go out at once.
p([10, 1023, 1024, 2000].map { |n| IO.pipe { |r, w| w.write(*(["a"] * n)); r.read_nonblock(n).size } })
require "tmpdir"
Dir.mktmpdir do |dir|
  path = File.join(dir, "f")
  File.open(path, "w") { |f| f.write("x"); f.sync = true }
  p File.read(path)
  File.open(path, "w") { |f| f.write("x"); f.sync = true; f.write("y") }
  p File.read(path)
end
$stdout.flush
$stdout.sync = false
print "dropped at exit"
$stdout.sync = true
