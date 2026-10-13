# ruby 4.1's queue_initialize gives a queue a new buffer but keeps the old
# count, so a queue initialized again still says it holds its old items,
# whose slots now hold memory that nothing wrote (thread_sync.c). zr
# empties the queue. Only the count is printed: the items are undefined.
q = Queue.new
q << 1
q.send(:initialize)
p q.size
r = Queue.new([1, 2, 3])
r.send(:initialize, [9])
p [r.size, r.pop]
