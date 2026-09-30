# Every wait reads its timeout before it parks, and two rules apply: a
# sleep takes a time interval, which refuses a negative one, while a
# limit (a queue's timeout, a join's) takes what rb_to_float takes and
# answers at once when the limit has passed.
def t = yield rescue [$!.class, $!.message]

m = Thread::Mutex.new
p t { m.synchronize { m.sleep(:x) } }
p t { m.synchronize { m.sleep("2") } }
p t { m.synchronize { m.sleep(-1) } }
cv = Thread::ConditionVariable.new
p t { m.synchronize { cv.wait(m, :x) } }

q = Thread::Queue.new
p t { q.pop(timeout: :x) }
p t { q.pop(timeout: "2") }
p t { q.pop(timeout: -1) }

s = Thread::SizedQueue.new(1)
s << 1
p t { s.push(2, timeout: :x) }
p t { s.push(2, timeout: -1) }

p t { Thread.new { 1 }.join(:x) }
p t { Thread.new { 1 }.join("2") }

