# IO::Buffer#read, #write, #pread and #pwrite make the system call over
# the rest of the buffer until at least `length` bytes moved, and answer
# the count or the negative errno.
require "tmpdir"
require "io/nonblock"
Warning[:experimental] = false
r, w = IO.pipe
b = IO::Buffer.new(8)
p b.write(w, 0), IO::Buffer.for("hey").write(w, 2, 1)
w.write("abc")
p b.read(r, 3), b.get_string(0, 5)
p b.read(r, 0), b.get_string(0, 5)
r.nonblock = true
p b.read(r, 0) == -Errno::EAGAIN::Errno
w.close
p b.read(r, 0), (b.read(r, 1, 9) rescue $!), (b.read(r, 20) rescue $!), (b.read(r, -1) rescue $!)
p (IO::Buffer.for("x").read(r, 1) rescue $!.class), (b.read(3, 1) rescue $!)
Dir.mktmpdir do |dir|
  path = File.join(dir, "bytes")
  File.write(path, "0123456789")
  File.open(path, "r+") do |f|
    c = IO::Buffer.new(4)
    p c.pread(f, 3, 4), c.get_string, f.pos
    p IO::Buffer.for("ZZ").pwrite(f, 8), f.pos
  end
  p File.read(path)
end


