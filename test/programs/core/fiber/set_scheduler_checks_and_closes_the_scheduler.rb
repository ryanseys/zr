# Fiber.set_scheduler checks the hooks a scheduler needs, fiber_interrupt
# too since ruby 4.1; Fiber.schedule runs the fiber hook, a sleep in it
# reaches kernel_sleep, and setting nil closes the scheduler.
class S
  def initialize; @ready = []; @log = []; end
  attr_reader :log
  def kernel_sleep(d = nil) = (@log << :sleep; Fiber.yield)
  def block(blocker, timeout = nil) = (@log << :block; Fiber.yield)
  def unblock(blocker, fiber) = (@log << :unblock; @ready << fiber)
  def io_wait(io, events, timeout) = (@log << :io_wait; events)
  def fiber(&b) = Fiber.new(blocking: false, &b).tap(&:resume)
  def fiber_interrupt(fiber, exception) = fiber.raise(exception)
  def close = (@log << :close)
  def run; end
end
s = S.new
Fiber.set_scheduler(s)
p Fiber.scheduler.equal?(s)
Fiber.schedule { sleep 1; :x }
p s.log
Fiber.set_scheduler(nil)
p s.log.last
begin
  Fiber.set_scheduler(Object.new)
rescue ArgumentError => e
  p e.message
end
p((Fiber.schedule {} rescue $!))

# Each hook but fiber_interrupt is not enough.
class NoInterrupt < S
  undef_method :fiber_interrupt
end
begin
  Fiber.set_scheduler(NoInterrupt.new)
rescue ArgumentError => e
  p e.message
end
p Fiber.scheduler
