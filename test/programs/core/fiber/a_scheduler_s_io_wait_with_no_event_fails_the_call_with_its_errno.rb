# A read or write that a scheduler's io_read or io_write answers with
# EAGAIN waits in its io_wait. nil or 0 from io_wait is no event, and the
# call fails with EAGAIN, though the wait cleared errno; false is a
# timeout, as rb_io_maybe_wait_readable reads it.
Warning[:experimental] = false

class Refusing
  def initialize(answer) = @answer = answer
  def io_read(*) = -Errno::EAGAIN::Errno
  alias io_write io_read

  def io_wait(*)
    Fiber.blocking { File.read(File::NULL) }
    @answer
  end

  def block(*) = nil
  def unblock(*) = nil
  def kernel_sleep(*) = nil
  def fiber_interrupt(*) = nil
  def close = nil
  def fiber(&block) = Fiber.new(blocking: false, &block).tap(&:resume)
end

seen = []
[nil, 0, false].each do |answer|
  Thread.new do
    Fiber.set_scheduler(Refusing.new(answer))
    IO.pipe do |reader, writer|
      Fiber.schedule do
        [-> { reader.read(1) }, -> { reader.readpartial(1) }, -> { reader.getc }, -> { reader.sysread(1) },
         -> { writer.write("hello") }].each do |call|
          call.call
        rescue SystemCallError, IO::TimeoutError => e
          seen << [answer, e.class, e.message]
        end
      end
    end
  end.join
end
seen.each { |row| p row.map { |part| part.is_a?(String) ? part.sub(/fd:\d+/, "fd:N") : part } }
