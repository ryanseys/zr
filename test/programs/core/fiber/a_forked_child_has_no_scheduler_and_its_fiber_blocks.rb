# In a forked child the scheduler is cleared, with no close, and the
# fiber that forked becomes the blocking root, as rb_thread_atfork and
# rb_fiber_atfork leave them.
Warning[:experimental] = false

class Plain
  def block(*) = nil
  def unblock(*) = nil
  def kernel_sleep(*) = nil
  def io_wait(*) = nil
  def fiber_interrupt(*) = nil
  def close = $stdout.puts("close in #{$$ == PARENT ? "parent" : "child"}")
  def fiber(&block) = Fiber.new(blocking: false, &block).tap(&:resume)
end
PARENT = $$

Thread.new do
  r, w = IO.pipe
  Fiber.set_scheduler Plain.new
  pid = fork do
    r.close
    w << [Fiber.scheduler.inspect, Fiber.current.blocking?, Fiber.blocking?].inspect
    w.close
  end
  w.close
  puts r.read
  Process.wait(pid)
  r.close
end.join

Thread.new do
  r, w = IO.pipe
  Fiber.set_scheduler Plain.new
  pid = nil
  Fiber.schedule do
    pid = fork do
      r.close
      w << [Fiber.scheduler.inspect, Fiber.current.blocking?, Fiber.blocking?].inspect
      w.close
    end
  end
  w.close
  puts r.read
  Process.wait(pid)
  r.close
end.join
