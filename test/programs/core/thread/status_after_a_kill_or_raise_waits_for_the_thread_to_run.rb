# Thread#kill and Thread#raise change no status until the target runs:
# a sleeping thread still shows "sleep", and a
# running one shows "run", not "aborting". Thread#wakeup shows "run" at
# once.
t = Thread.new { sleep }
Thread.pass until t.stop?
t.kill
p [:kill_sleep, t.status]
t.join
t = Thread.new { Thread.current.report_on_exception = false; sleep }
Thread.pass until t.stop?
t.raise "x"
p [:raise_sleep, t.status]
t.join rescue p $!.message
t = Thread.new { sleep }
Thread.pass until t.stop?
t.wakeup
p [:wakeup_sleep, t.status]
t.join
q = Queue.new
t = Thread.new { q.pop }
Thread.pass until t.stop?
t.kill
p [:kill_pop, t.status]
t.join
m = Mutex.new
m.lock
t = Thread.new { m.lock }
Thread.pass until t.stop?
t.kill
p [:kill_lock, t.status]
m.unlock
t.join
p [:after, t.status]
t = Thread.new { loop { Thread.pass } }
sleep 0.01
t.kill
p [:kill_running, t.status]
t.join
