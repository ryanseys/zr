# A thread of higher priority keeps its turn longer, so it counts much
# further than one of lower priority in the same time; a new thread
# starts with its creator's priority.
c1 = c2 = 0
run = true
t1 = Thread.new { c1 += 1 while run }
t1.priority = 3
t2 = Thread.new { c2 += 1 while run }
t2.priority = -3
p [t1.priority, t2.priority]
sleep 1
run = false
[t1, t2].each(&:join)
p c1 > c2 * 2

# Equal priorities both run.
a = b = 0
run = true
ta = Thread.new { a += 1 while run }
tb = Thread.new { b += 1 while run }
sleep 0.5
run = false
[ta, tb].each(&:join)
p a.positive? && b.positive?

Thread.current.priority = 2
p Thread.new { Thread.current.priority }.value
Thread.current.priority = 0
p Thread.new { Thread.current.priority = 10; Thread.current.priority }.value
