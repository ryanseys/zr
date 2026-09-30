# SizedQueue bounds #push; Mutex#try_lock is non-blocking; and the whole
# Thread::* family reports its CRuby-faithful qualified name.

p Queue
p SizedQueue
p Mutex
q = SizedQueue.new(2)
p q.class
p q.is_a?(Queue)
p q.max
producer = Thread.new do
  5.times { |i| q.push(i) }
  q.close
end
got = []
while (v = q.pop)
  got << v
end
producer.join
p got
s = SizedQueue.new(3)
s << "a" << "b"
p s.size
s.max = 5
p s.max
m = Mutex.new
p m.try_lock
p m.try_lock
m.unlock
p m.try_lock
m.unlock
