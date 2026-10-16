# A thread is joinable once its body ends, before its joiners wake: a
# scheduler whose unblock sleeps runs that sleep in the finishing thread,
# and the fiber that joined it gets its value and does not wait again
# (thread_start_func_2 sets th->value before the join list wakes).
require_relative "fiber_scheduler/scheduler"
Warning[:experimental] = false

inner = nil
got = nil
thread = Thread.new do
  scheduler = SleepingUnblockScheduler.new
  Fiber.set_scheduler scheduler
  Fiber.schedule do
    inner = Thread.new { sleep(0.01); :inner }
    got = inner.value
  end
end
thread.join
p got
inner.join
p [inner.value, inner.status]
