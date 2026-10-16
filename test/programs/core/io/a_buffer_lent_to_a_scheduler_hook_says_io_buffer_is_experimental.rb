# rb_io_buffer_new allocates an IO::Buffer, so the first buffer that the
# runtime lends a scheduler's io_read gives ruby's experimental warning,
# at the line that reads. It is said once.
class LendingScheduler
  def io_read(io, buffer, offset, length)
    Fiber.blocking { buffer.read(io, offset, length) }
  end

  def io_wait(_io, events, _timeout) = events
  def kernel_sleep(*) = nil
  def block(*) = nil
  def unblock(*) = nil
  def fiber_interrupt(*) = nil
  def fiber(&) = Fiber.new(blocking: false, &).tap(&:resume)
  def close = nil
end

reader, writer = IO.pipe
writer.write("hello")
writer.close
Thread.new do
  Fiber.set_scheduler LendingScheduler.new
  Fiber.schedule do
    p reader.read(3)
    p reader.read(2)
  end
end.join
$stderr.puts "after"
p IO::Buffer.new(4).size
