# A parked thread's backtrace starts at the call that waits, and its
# inspect shows sleep_forever for a wait that counts toward a deadlock.
q = Thread::Queue.new
m = Mutex.new
m.lock
cv = ConditionVariable.new
r, _w = IO.pipe
def inner(q) = q.pop
ts = [Thread.new { q.pop }, Thread.new { inner(q) }, Thread.new { sleep }, Thread.new { sleep 5 },
      Thread.new { m.lock }, Thread.new { r.read(1) }, Thread.new { Thread.stop },
      Thread.new { m2 = Mutex.new; m2.synchronize { cv.wait(m2) } }, Thread.new { m2 = Mutex.new; m2.synchronize { cv.wait(m2, 5) } }]
Thread.pass until ts.all?(&:stop?)
ts.each do |t|
  p t.backtrace.map { |line| line.sub(%r{\A.*/}, "") }
  puts t.inspect.sub(/0x\h+/, "X").sub(%r{ \S*/}, " ")
end

# A child forked while a mutex is locked unlocks it there, though the
# parent's waiters are dead in the child.
lock = Mutex.new
waiters = []
lock.synchronize do
  waiters = [Thread.new { lock.synchronize {} }]
  Thread.pass until waiters.all?(&:stop?)
  pid = fork do
    lock.locked? or exit!(2)
    mine = Thread.new { lock.synchronize { :got } }
    lock.unlock
    exit!(mine.join(1) && mine.value == :got ? 0 : 1)
  end
  p Process.waitpid2(pid).last.exitstatus
end
p waiters.map { |t| t.join(1).equal?(t) }
