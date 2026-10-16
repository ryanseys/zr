# ruby 4.1's queue_initialize gives a queue a new buffer but keeps the old
# count and the old offset, so a queue initialized again still says it
# holds its old items. Their slots hold memory that nothing wrote
# (thread_sync.c), so only the counts are printed; zr's slots read nil.
q = Queue.new
q << 1
q.send(:initialize)
p q.size, q.empty?, q.length
q << 5
p q.size
r = Queue.new([1, 2, 3])
r.send(:initialize, [9])
p [r.size, r.pop]
s = Queue.new
s.send(:initialize)
p s.size
u = Queue.new([1, 2])
u.send(:initialize, [])
p u.size
