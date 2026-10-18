# Each thread runs on an OS thread of its own (ZR_THREADS=native in the
# .env); the answers are the same as with green threads.
q = Queue.new
producer = Thread.new { 5.times { |i| q << i }; :done }
p producer.value
p 5.times.map { q.pop }

sums = 6.times.map { |n| Thread.new(n) { |k| (1..50_000).sum { |i| i * k } } }
p sums.map(&:value)

m = Mutex.new
count = 0
3.times.map { Thread.new { 2_000.times { m.synchronize { count += 1 } } } }.each(&:join)
p count

# Many short threads: each OS thread ends after it hands the GVL on.
p 200.times.map { |i| Thread.new { i * 2 } }.sum(&:value)

# A collection while other threads wait reads their stacks.
keep = 4.times.map do |i|
  Thread.new do
    data = Array.new(1_000) { |j| "s#{i}-#{j}" }
    Thread.stop
    data.last
  end
end
Thread.pass until keep.all?(&:stop?)
GC.start
keep.each(&:wakeup)
p keep.map(&:value)

# Fibers inside a thread run on that thread's OS thread.
p Thread.new { f = Fiber.new { Fiber.yield :a; :b }; [f.resume, f.resume] }.value

# A deep recursion inside a thread.
def depth(n) = n.zero? ? 0 : 1 + depth(n - 1)
p Thread.new { depth(5_000) }.value

# An exception goes to join.
t = Thread.new { raise ArgumentError, "inside" }
t.report_on_exception = false
begin
  t.join
rescue ArgumentError => e
  p e.message
end

# A condition variable hands control back and forth.
cv = ConditionVariable.new
turn = :a
log = []
b = Thread.new do
  m.synchronize do
    3.times do
      cv.wait(m) until turn == :b
      log << :b
      turn = :a
      cv.signal
    end
  end
end
m.synchronize do
  3.times do
    log << :a
    turn = :b
    cv.signal
    cv.wait(m) until turn == :a
  end
end
b.join
p log

# A ractor's class is its own, also when main runs on another OS thread.
r = Ractor.new { Class.new { const_set(:LIST, [1]) } }
klass = r.value
begin
  klass::LIST
rescue Ractor::IsolationError => e
  p e.class
end
p Thread.list.size
