# With an OS thread for each thread (ZR_THREADS=native in the .env), a
# signal that another thread sends runs its trap on the main thread,
# also while the main thread waits; and a deadlock is reported.
q = Queue.new
trap(:USR1) { q << [:trapped, Thread.current == Thread.main] }
sender = Thread.new do
  sleep 0.05
  Process.kill(:USR1, Process.pid)
  :sent
end
p q.pop, sender.value

trap(:USR2) { q << :while_sleeping }
Thread.new do
  sleep 0.05
  Process.kill(:USR2, Process.pid)
end
sleep 0.3
p q.pop

# A worker that computes while the signal comes: the main thread runs
# the trap, at its next turn.
worker = Thread.new do
  x = 0
  2_000_000.times { x += 1 }
  x
end
Process.kill(:USR1, Process.pid)
p q.pop, worker.value

# Every thread waits for good: a deadlock.
m = Mutex.new
m.lock
waiter = Thread.new { m.lock }
Thread.pass until waiter.stop?
begin
  Thread.new { Queue.new.pop }.join
rescue Exception => e
  puts e.class, e.message.lines.first
  puts e.message.scan(/native:0x\h+/).size
end
