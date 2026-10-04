# Queue and SizedQueue refuse a true or false timeout, a pop that may
# not wait raises before a closed queue's nil, a SizedQueue's size goes
# through to_int, and ConditionVariable#wait sends sleep to what it gets.
def t
  yield
rescue => e
  [e.class, e.message]
end
q = Queue.new
s = SizedQueue.new(1)
p t { q.pop(timeout: true) }, t { s.push(1, timeout: false) }, t { s.pop(timeout: true) }
q.close
s.close
p t { q.pop(true) }, t { s.pop(true) }, t { q.pop }
p t { SizedQueue.new(Object.new) }, t { SizedQueue.new(1.9).max }, t { SizedQueue.new(1).max = "a" }
o = Object.new
def o.sleep(t) = (p [:slept, t]; :r)
p ConditionVariable.new.wait(o, 1234), ConditionVariable.new.wait(o)
