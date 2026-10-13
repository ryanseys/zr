# Code that a trap handler runs may not lock a Mutex (or enter a
# Monitor that it does not hold): ruby raises ThreadError there, because
# the interrupted code may hold the lock. A fiber that the handler
# resumes is in the handler too. try_lock, a thread that the handler
# starts, and the code after the handler may lock.
require "monitor"

m = Mutex.new
mon = Monitor.new
seen = []
trap(:USR1) do
  [-> { m.lock }, -> { m.synchronize { 1 } }, -> { mon.enter }, -> { mon.synchronize { 1 } }].each do |call|
    call.call
    seen << :locked
  rescue ThreadError => e
    seen << e.message
  end
  seen << m.try_lock
  m.unlock
  seen << Thread.new { m.synchronize { :in_thread } }.value
  seen << begin
    Fiber.new { m.synchronize { :in_fiber } }.resume
  rescue ThreadError => e
    e.message
  end
end
Process.kill(:USR1, $$)
sleep 0.1
p seen
p m.synchronize { :after }

mon.enter
trap(:USR2) { seen = [mon.mon_owned?]; mon.enter; seen << :reentered; mon.exit }
Process.kill(:USR2, $$)
sleep 0.1
p seen
