# A non-blocking fiber's reads and writes reach its scheduler's io_read,
# io_write, io_pread and io_pwrite with an IO::Buffer, in the sizes io.c
# reads and writes with. This runtime reads and writes itself and hands
# the scheduler only io_wait, so a scheduler that logs its hooks sees none.
require_relative "../core/fiber/a_fiber_scheduler_takes_every_blocking_operation/scheduler"
require "tmpdir"
class Logged < IOBufferScheduler
  attr_reader :calls
  def initialize(*) = (super; @calls = [])
  def io_read(io, buffer, length, offset)
    @calls << [:io_read, io.class, buffer.size, buffer.external?, buffer.locked?, length, offset]
    super
  end
  def io_write(io, buffer, length, offset)
    @calls << [:io_write, io.class, buffer.size, buffer.get_string(offset, [buffer.size - offset, 12].min), length, offset]
    super
  end
  def io_pread(io, buffer, from, length, offset)
    @calls << [:io_pread, from, length, offset]
    super
  end
  def io_pwrite(io, buffer, from, length, offset)
    @calls << [:io_pwrite, from, length, offset]
    super
  end
end
log = []
sched = nil
Thread.new do
  sched = Logged.new
  Fiber.set_scheduler(sched)
  r, w = IO.pipe
  Fiber.schedule { log << r.read(5); log << r.gets; log << r.readpartial(10); log << r.read }
  Fiber.schedule { w.write("hello"); w.sync = false; w.print("line\n"); w.flush; w.syswrite("more"); sleep 0.01; w.close }
  Fiber.schedule do
    File.open(__FILE__) { |f| log << f.read(7); log << f.pread(4, 2) }
    path = File.join(Dir.tmpdir, "hooks#{$$}")
    File.open(path, "w") { |f| f.write("abc"); f.pwrite("Z", 1) }
    log << File.read(path)
    File.delete(path)
  end
end.join
p log
sched.calls.each { |c| p c }

__END__
["hello", "line\n", "more", "# A non", "A no", "abc", ""]
[:io_read, IO, 5, false, true, 0, 0]
[:io_write, IO, 5, "hello", 0, 0]
[:io_write, IO, 5, "line\n", 0, 0]
[:io_write, IO, 4, "more", 0, 0]
[:io_read, IO, 5, false, true, 0, 0]
[:io_read, IO, 8192, false, true, 0, 0]
[:io_read, IO, 1024, false, true, 0, 0]
[:io_read, File, 7, false, true, 0, 0]
[:io_pread, 2, 0, 0]
[:io_pwrite, 1, 0, 0]
[:io_write, File, 3, "abc", 0, 0]
[:io_read, File, 3, false, true, 0, 0]
[:io_read, File, 1024, false, true, 0, 0]
[:io_read, IO, 1024, false, true, 0, 0]
