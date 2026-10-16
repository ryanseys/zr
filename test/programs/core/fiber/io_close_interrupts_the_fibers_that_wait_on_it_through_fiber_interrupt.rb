# IO#close interrupts each fiber that waits on the IO under a scheduler:
# the scheduler's fiber_interrupt gets a target, whose transfer raises
# the close's IOError in the fiber, and the close waits until the fiber's
# operation ends (thread_io_close_notify_all). After that the target is
# inactive. A thread with no scheduler gets the IOError as it waits.
# scheduler.rb is CRuby's test/fiber/scheduler.rb.
require "socket"
require "io/wait"
require_relative "scheduler"

puts "== a fiber closes what another reads"
reader, _writer = UNIXSocket.pair
error = nil
Thread.new do
  Fiber.set_scheduler Scheduler.new
  Fiber.schedule do
    reader.read
  rescue => e
    error = e
  end
  Fiber.schedule { reader.close }
end.join
p error

puts "== the interrupt stays in its operation"
source, _source_peer = UNIXSocket.pair
unrelated, _unrelated_peer = UNIXSocket.pair
errors = []
Thread.new do
  Fiber.set_scheduler Scheduler.new
  5.times do
    Fiber.schedule do
      begin
        source.wait_readable(0.01)
        source.close
      rescue => e
        errors << [:source, e.class, e.message]
      end
      begin
        unrelated.wait_readable(0.01)
      rescue => e
        errors << [:unrelated, e.class, e.message]
      end
    end
  end
end.join
p errors

puts "== another thread closes what a fiber reads"
reader, _writer = UNIXSocket.pair
error = nil
scheduler = nil
recording = Class.new(Scheduler) do
  attr_reader :interrupt_target

  def fiber_interrupt(target, exception)
    @interrupt_target = target
    super
  end
end
thread = Thread.new do
  scheduler = recording.new
  Fiber.set_scheduler scheduler
  Fiber.schedule do
    reader.read
  rescue => e
    error = e
  end
end
Thread.pass until thread.status == "sleep"
reader.close
thread.join
p error
target = scheduler.interrupt_target
p target.class.name, target.class.superclass, target.alive?, target.transfer, target.raise(IOError.new)
p((target.class.allocate rescue $!.class), (target.class.new rescue $!.class))

puts "== a fiber closes what a thread reads"
reader, _writer = UNIXSocket.pair
error = nil
waiting = Thread.new do
  reader.read
rescue => e
  error = e
end
Thread.pass until waiting.status == "sleep"
Thread.new do
  Fiber.set_scheduler Scheduler.new
  Fiber.schedule { reader.close }
end.join
waiting.join
p error
