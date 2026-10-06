# The threads that wait on a queue or a condition variable stay in the
# parent: in a forked child the lists are empty, and the queues work.
q = Thread::Queue.new
sq = Thread::SizedQueue.new(1)
cv = Thread::ConditionVariable.new
m = Thread::Mutex.new
thq = Thread.new { q.pop }
thsq = Thread.new { sq.pop }
sq2 = Thread::SizedQueue.new(1)
sq2.push(0)
thpush = Thread.new { sq2.push(1) }
thcv = Thread.new { m.synchronize { cv.wait(m) } }
Thread.pass until thq.stop? && thsq.stop? && thpush.stop? && thcv.stop?
p [q.num_waiting, sq.num_waiting, sq2.num_waiting]
pid = fork do
  p [q.num_waiting, sq.num_waiting, sq2.num_waiting]
  q.push :child_q
  sq.push :child_sq
  p [q.pop, sq.pop, sq2.pop, sq2.size]
  cv.signal
  cv.broadcast
  p :child_done
  exit!(0)
end
p Process.waitpid2(pid)[1].success?
q.push :thq
sq.push :thsq
p [thq.value, thsq.value]
p [sq2.pop, thpush.join && sq2.pop]
m.synchronize { cv.signal }
thcv.join
p :parent_done
frozen = Thread::ConditionVariable.new.freeze
frozen.signal
p frozen.frozen?
