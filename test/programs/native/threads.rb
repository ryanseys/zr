# Threads switch stacks with a raw function.
t = Thread.new { :done }
p t.class, t.alive?, t.join.equal?(t), t.value, t.alive?, t.status, t.stop?
p Thread.current.class, Thread.main.equal?(Thread.current), Thread.current.alive?, Thread.current.status, Thread.main.stop?
order = []
a = Thread.new { order << :a1; Thread.pass; order << :a2 }
b = Thread.new { order << :b1; Thread.pass; order << :b2 }
order << :main
a.join
b.join
p order
p Thread.new(1, 2) { |x, y| x + y }.value
begin
  Thread.new
rescue ThreadError => e
  p e.message
end
q = Queue.new
producer = Thread.new { 3.times { |i| q << i }; q.close }
got = []
while (v = q.pop)
  got << v
end
producer.join
p got, q.closed?, q.empty?, q.size, q.pop
q2 = Queue.new
consumer = Thread.new { [q2.pop, q2.pop] }
q2.push(:x)
q2 << :y
p consumer.value, q2.num_waiting
begin
  q2.pop(true)
rescue ThreadError => e
  p e.message
end
p q2.pop(timeout: 0.01), Queue.new([1, 2]).size, q2.length, (q2 << 1).equal?(q2), q2.shift, q2.deq(true) rescue p $!
q3 = Queue.new
q3.close
begin
  q3.push(1)
rescue ClosedQueueError => e
  p e.message, e.class.ancestors.include?(StopIteration)
end
sq = SizedQueue.new(1)
p sq.max
filler = Thread.new { [1, 2, 3].each { |i| sq.push(i) }; :filled }
p sq.pop, sq.pop, sq.pop, filler.value
begin
  sq.push(1)
  sq.push(2, true)
rescue ThreadError => e
  p e.message
end
m = Mutex.new
p m.locked?, m.lock.equal?(m), m.locked?, m.owned?, m.try_lock, m.unlock.equal?(m), m.try_lock, m.locked?
m.unlock
begin
  m.unlock
rescue ThreadError => e
  p e.message
end
m.lock
begin
  m.lock
rescue ThreadError => e
  p e.message
end
m.unlock
p m.synchronize { m.locked? }, m.locked?
counter = 0
workers = 4.times.map do |i|
  Thread.new do
    10.times do
      m.synchronize do
        c = counter
        Thread.pass
        counter = c + 1
      end
    end
  end
end
workers.each(&:join)
p counter
locker = Thread.new { m.synchronize { Thread.pass; :inside } }
Thread.pass
p m.locked?, (m.try_lock), locker.value, m.locked?
other = Thread.new { m.lock; Thread.stop; m.unlock; :released }
Thread.pass
p m.locked?, other.status, other.stop?
begin
  m.unlock
rescue ThreadError => e
  p e.message
end
other.wakeup
p other.value, m.locked?
cv = ConditionVariable.new
ready = false
waiter = Thread.new { m.synchronize { cv.wait(m) until ready; :woke } }
Thread.pass
m.synchronize { ready = true; cv.signal }
p waiter.value
ws = 3.times.map { Thread.new { m.synchronize { cv.wait(m); :w } } }
Thread.pass
m.synchronize { cv.broadcast }
p ws.map(&:value)
bad = Thread.new { raise ArgumentError, "inside" }
bad.report_on_exception = false
begin
  bad.join
rescue ArgumentError => e
  p e.message, bad.status, bad.alive?
end
begin
  bad.value
rescue ArgumentError => e
  p e.message
end
p Thread.report_on_exception
Thread.report_on_exception = false
quiet = Thread.new { raise "quiet" }
p((quiet.join rescue $!.message))
Thread.report_on_exception = true
k = Thread.new { Thread.stop; :never }
Thread.pass
p k.status, k.kill.equal?(k), k.join.equal?(k), k.value, k.status, k.alive?
cleaned = []
k2 = Thread.new do
  begin
    Thread.stop
  ensure
    cleaned << :ensure
  end
  cleaned << :after
end
Thread.pass
k2.kill
k2.join
p cleaned
k3 = Thread.new { Thread.current.kill; :no }
p k3.value, k3.status
k4 = Thread.new { Thread.exit; :no }
p k4.join.status
p Thread.current[:x], (Thread.current[:x] = 1), Thread.current[:x], Thread.current.key?(:x), Thread.current.key?(:y), Thread.current.keys
loc = Thread.new { Thread.current[:x] = 2; Thread.current[:x] }
p loc.value, Thread.current[:x], Thread.current["x"], Fiber.new { Thread.current[:x] }.resume
Thread.current.thread_variable_set(:tv, 5)
p Thread.current.thread_variable_get(:tv), Thread.current.thread_variable?(:tv), Thread.current.thread_variables, Fiber.new { Thread.current.thread_variable_get(:tv) }.resume
n = Thread.new { Thread.current.name }
p n.value, Thread.current.name, (Thread.current.name = "main"), Thread.current.name
begin
  Thread.current.join
rescue ThreadError => e
  p e.message
end
p Thread.new { (Thread.main.join rescue $!.message) }.value
p Thread.list.size, Thread.list.include?(Thread.current)
sleeper = Thread.new { sleep 0.01; :slept }
p sleeper.join(0.001), sleeper.status, sleeper.join(5).equal?(sleeper), sleeper.value
p sleep(0.001), sleep(0), Thread.new { sleep }.tap { |z| Thread.pass; p z.status; z.wakeup }.join.status
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sleep 0.02
p Process.clock_gettime(Process::CLOCK_MONOTONIC) - start >= 0.02, Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond).class, Process::CLOCK_REALTIME.class
stopped = Thread.new { Thread.stop; :resumed }
Thread.pass
p stopped.status, stopped.run.equal?(stopped), stopped.value
gen = Thread.new do
  fib = Fiber.new { Fiber.yield 1; 2 }
  [fib.resume, fib.resume, Thread.current.equal?(Thread.main)]
end
p gen.value
nested = Thread.new { Thread.new { Thread.new { :deep }.value }.value }
p nested.value
p Thread.new { Thread.current.alive? }.value, Thread.new { Thread.current.status }.value
z = Thread.new { GC.start; s = +""; 5.times { |i| s << i.to_s; Thread.pass; GC.start }; s }
zz = Thread.new { GC.start; [1, 2].map { |i| Thread.pass; i * 2 } }
p z.value, zz.value
p Thread.new { Thread.current.inspect.start_with?("#<Thread:0x") }.value, Thread.current.to_s.end_with?(" run>")
p Thread.new { Thread.current.report_on_exception }.value, Thread.abort_on_exception, Thread.new { Thread.current.abort_on_exception }.value
aborter = Thread.new { Thread.current.report_on_exception = false; raise IOError, "abort" }
aborter.abort_on_exception = true
begin
  sleep
rescue IOError => e
  p e.message
end
p Thread.start { 7 }.value, Thread.fork { 8 }.value
e2 = Thread.new { Thread.current.report_on_exception = false; raise "x" }
p (e2.join rescue $!.class), e2.status, (e2.value rescue $!.message)
p Thread.new { Thread.current.join rescue $!.message }.value
at_exit { p :at_exit }
Thread.new { sleep 0.001; Thread.main.raise ArgumentError, "from thread" }
begin
  sleep
rescue ArgumentError => e
  p e.message
end
p Thread.new { loop { Thread.stop } }.tap { |w| Thread.pass; w.wakeup; Thread.pass; w.kill; w.join }.status
