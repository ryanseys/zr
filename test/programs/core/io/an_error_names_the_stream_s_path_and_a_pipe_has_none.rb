# An IO error names the stream as rb_sys_fail_path(fptr->pathv) does:
# its path, or the name of a standard stream. A pipe, a socket and an IO
# made from a descriptor have no path, so the message is the errno's text.
require "socket"
require "tmpdir"

def show(label)
  yield
  puts "#{label}: no error"
rescue SystemCallError, IOError => e
  message = $dir ? e.message.sub($dir, "DIR") : e.message
  puts "#{label}: #{e.class}: #{message}"
end

r, w = IO.pipe
r.close
show("write to a pipe whose reader closed") { w.write("x") }
show("syswrite to it") { w.syswrite("x") }
show("print to it") { w.print("x") }
show("write_nonblock to it") { w.write_nonblock("x") }

from_fd = IO.new(w.fileno, "w", autoclose: false)
from_fd.sync = true
show("write through IO.new of its descriptor") { from_fd.write("x") }

a, b = UNIXSocket.pair
b.close
show("write to a socket whose peer closed") { a.write("x") }

r2, w2 = IO.pipe
show("pos of a pipe") { r2.pos }
show("seek of a pipe") { r2.seek(1) }
show("pread of a pipe") { r2.pread(1, 0) }

show("seek of STDIN on a pipe") do
  saved = $stdin.dup
  $stdin.reopen(r2)
  begin
    $stdin.seek(1)
  ensure
    $stdin.reopen(saved)
  end
end

Dir.mktmpdir do |dir|
  $dir = dir
  path = File.join(dir, "fifo")
  File.mkfifo(path)
  reader = Thread.new { File.open(path, "r") { |f| f.read(1) } }
  File.open(path, "w") do |f|
    f.write("x")
    f.flush
    reader.join
    show("seek of a fifo opened by path") { f.seek(1) }
    show("pos of it") { f.pos }
  end
end
