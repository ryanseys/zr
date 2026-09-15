# A thread with a fiber scheduler hands each blocking operation of its
# non-blocking fibers to the scheduler: sleep, a pipe read and write, a
# Mutex, a Queue, a Thread#value, Process.wait, Timeout.timeout,
# getaddrinfo and a close. The scheduler is CRuby's own test scheduler
# (test/fiber/scheduler.rb at ruby 4.0.6), unedited.
require_relative "a_fiber_scheduler_takes_every_blocking_operation/scheduler"
require "timeout"
log = []
thread = Thread.new do
  scheduler = Scheduler.new
  Fiber.set_scheduler(scheduler)
  p [Fiber.scheduler.class, Fiber.current_scheduler, Fiber.blocking?]

  Fiber.schedule { log << :a1; sleep 0.02; log << :a2 }
  Fiber.schedule { log << :b1; sleep 0.01; log << :b2 }

  r, w = IO.pipe
  Fiber.schedule { log << [:read, r.read(5)] }
  Fiber.schedule { sleep 0.03; w.write("hello"); w.close }

  m = Thread::Mutex.new
  q = Thread::Queue.new
  Fiber.schedule { m.synchronize { sleep 0.01; log << :locked_first } }
  Fiber.schedule { m.synchronize { log << :locked_second } }
  Fiber.schedule { log << [:popped, q.pop] }
  Fiber.schedule { q << :item }

  Fiber.schedule { log << [:joined, Thread.new { sleep 0.01; :t }.value] }
  Fiber.schedule do
    pid = Process.spawn("exit 7")
    Process.wait(pid)
    log << [:status, $?.exitstatus]
  end
  Fiber.schedule do
    Timeout.timeout(0.01) { sleep 1 }
  rescue Timeout::Error => e
    log << [:timeout, e.class]
  end
  Fiber.schedule { log << [:resolved, Addrinfo.getaddrinfo("localhost", 80).map(&:ip_address).uniq.sort.first] }
  Fiber.schedule { log << [:current, Fiber.current_scheduler.class, Fiber.blocking { Fiber.current_scheduler }] }
end
thread.join
p log.sort_by(&:to_s)
p Fiber.scheduler
__END__
[Scheduler, nil, 1]
[[:current, Scheduler, nil], [:joined, :t], [:popped, :item], [:read, "hello"], [:resolved, "127.0.0.1"], [:status, 7], [:timeout, Timeout::Error], :a1, :a2, :b1, :b2, :locked_first, :locked_second]
nil
