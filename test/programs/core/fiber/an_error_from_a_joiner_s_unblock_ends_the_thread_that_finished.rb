# When a thread ends, it wakes its joiners. A joiner that waits in a
# fiber goes back through its scheduler's unblock, and an error there
# ends the finishing thread with that error, which the join raises, as
# rb_threadptr_join_list_wakeup runs inside the thread's own tag.
require_relative "fiber_scheduler/scheduler"
Warning[:experimental] = false

thread = Thread.new do
  Thread.current.report_on_exception = false
  scheduler = BrokenUnblockScheduler.new
  Fiber.set_scheduler scheduler
  Fiber.schedule do
    Thread.new { Thread.current.report_on_exception = false }.join
  rescue => e
    p [:joiner, e.class, e.message]
  end
  scheduler.run
ensure
  scheduler.close
end
begin
  thread.join
rescue => e
  p [:outer, e.class, e.message, e.backtrace_locations.map(&:label)]
end
p thread.status

reported = Thread.new do
  scheduler = BrokenUnblockScheduler.new
  Fiber.set_scheduler scheduler
  Fiber.schedule do
    Thread.new { :done }.join
  rescue => e
    p [:joiner, e.class, e.message]
  end
  scheduler.run
ensure
  scheduler.close
end
reported.join
p reported.status
