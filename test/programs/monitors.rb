# Monitor and MonitorMixin over green threads (native only).
p Monitor.new.class
m = Monitor.new
m.synchronize do
  m.synchronize { p m.mon_owned? }
  p m.mon_locked?
end
p m.mon_locked?
p(m.synchronize { 21 * 2 })
class Counter
  include MonitorMixin
  def initialize
    mon_initialize
    @n = 0
  end
  def bump; synchronize { @n += 1 }; end
  def reentrant; synchronize { synchronize { mon_owned? } }; end
  attr_reader :n
end
c = Counter.new
c.bump
c.bump
p c.n, c.reentrant, c.mon_owned?
o = Object.new
o.extend(MonitorMixin)
p o.synchronize { 1 }
mu = Mutex.new; cv = ConditionVariable.new
mu.synchronize { p cv.wait(mu, 0.01) }
mu.synchronize { p mu.sleep(0.01) }
t = Thread.new { mu.synchronize { p cv.wait(mu, 5) } }
sleep 0.05
mu.synchronize { cv.signal }
t.join
# monitor -- new_cond and MonitorMixin::ConditionVariable: the check-owner
# rules, a producer/consumer handoff, the timeout return, and the nesting
# count surviving a wait.

m = Monitor.new
c = m.new_cond
p c.class

begin
  c.signal
rescue ThreadError => e
  p e.class
end
begin
  c.wait
rescue ThreadError => e
  p e.class
end

buf = []
done = false
t = Thread.new do
  3.times do |i|
    m.synchronize do
      buf << i
      c.signal
    end
    sleep 0.01
  end
  m.synchronize do
    done = true
    c.signal
  end
end
got = []
m.synchronize do
  until done && buf.empty?
    c.wait_until { !buf.empty? || done }
    got.concat(buf)
    buf.clear
  end
end
t.join
p got.sort

m.synchronize do
  p c.wait(0.05)
end

# A wait from a NESTED enter releases the whole monitor and restores the
# nesting on wakeup.
m.synchronize do
  m.synchronize do
    p c.wait(0.05)
    p m.mon_owned?
  end
  p m.mon_owned?
end
p m.mon_locked?

class SharedBox
  include MonitorMixin
  def initialize
    super
    @items = []
  end

  def put(x)
    synchronize do
      @items << x
      @full ||= new_cond
      @full.signal
    end
  end

  def take
    synchronize do
      @full ||= new_cond
      @full.wait_while { @items.empty? }
      @items.shift
    end
  end
end

box = SharedBox.new
w = Thread.new { p box.take }
sleep 0.05
box.put(:handoff)
w.join
