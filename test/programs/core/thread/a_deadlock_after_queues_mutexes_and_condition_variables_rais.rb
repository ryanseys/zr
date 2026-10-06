def t(n)
  r = yield
  p [n, r]
rescue Exception => e
  p [n, :raise, e.class, e.message.lines.first.chomp]
end
$stderr.sync = true
t(:mpmc) do
  q = Thread::Queue.new
  prods = 8.times.map { |i| Thread.new { 1000.times { |j| q << i * 1000 + j } } }
  sum = Thread::Queue.new
  cons = 4.times.map { Thread.new { s = 0; while (v = q.pop); s += v; end; sum << s } }
  prods.each(&:join); q.close
  cons.each(&:join)
  4.times.map { sum.pop }.sum == (0...8000).sum
end
t(:sized_mpmc) do
  q = Thread::SizedQueue.new(3)
  got = []
  m = Mutex.new
  cons = 3.times.map { Thread.new { while (v = q.pop); m.synchronize { got << v }; end } }
  prods = 5.times.map { |i| Thread.new { 200.times { |j| q.push(i * 200 + j) } } }
  prods.each(&:join); q.close; cons.each(&:join)
  [got.size, got.sort == (0...1000).to_a, q.max]
end
t(:q_close) { q = Queue.new; q << 1; q.close; [q.closed?, q.pop, q.pop, q.empty?, q.size] }
t(:q_push_closed) { q = Queue.new; q.close; q << 1 }
t(:sq_push_closed) { q = SizedQueue.new(1); q.close; q << 1 }
t(:q_close_wakes) { q = Queue.new; th = Thread.new { q.pop }; sleep 0.05 until th.status == "sleep"; q.close; th.value }
t(:sq_close_wakes_pusher) { q = SizedQueue.new(1); q << 1; th = Thread.new { begin; q << 2; rescue => e; [e.class, e.message]; end }; sleep 0.05 until th.status == "sleep"; q.close; th.value }
t(:pop_timeout) { q = Queue.new; [q.pop(timeout: 0.05), q.pop(timeout: 0)] }
t(:pop_nonblock_timeout) { Queue.new.pop(true, timeout: 1) }
t(:pop_nonblock) { Queue.new.pop(true) }
t(:sq_push_timeout) { q = SizedQueue.new(1); q << 1; q.push(2, timeout: 0.05) }
t(:sq_push_nonblock) { q = SizedQueue.new(1); q << 1; q.push(2, true) }
t(:num_waiting) { q = Queue.new; ths = 3.times.map { Thread.new { q.pop } }; sleep 0.01 until q.num_waiting == 3; n = q.num_waiting; 3.times { q << 1 }; ths.each(&:join); [n, q.num_waiting] }
t(:sq_num_waiting) { q = SizedQueue.new(1); q << 0; ths = 2.times.map { Thread.new { q << 1 } }; sleep 0.01 until q.num_waiting == 2; n = q.num_waiting; 3.times { q.pop }; ths.each(&:join); n }
t(:q_init_enum) { Queue.new([1, 2, 3]).size }
t(:q_init_bad) { Queue.new(1) }
t(:q_freeze) { Queue.new.freeze }
t(:q_marshal) { Marshal.dump(Queue.new) }
t(:q_clear) { q = Queue.new([1, 2]); q.clear; q.length }
t(:sq_max) { q = SizedQueue.new(2); q.max = 5; [q.max, (q.max = 0 rescue [$!.class, $!.message])] }
t(:sq_new0) { SizedQueue.new(0) }
t(:q_alias) { q = Queue.new; q.enq(1); q.push(2); [q.deq, q.shift] }
t(:closed_q_err) { [ClosedQueueError.superclass, StopIteration.superclass] }
t(:cv) do
  m = Mutex.new; cv = ConditionVariable.new; ready = false; out = []
  ths = 5.times.map { |i| Thread.new { m.synchronize { cv.wait(m) until ready; out << i } } }
  sleep 0.01 until ths.all? { |th| th.status == "sleep" }
  m.synchronize { ready = true; cv.broadcast }
  ths.each(&:join); out.sort
end
t(:cv_signal_ret) { cv = ConditionVariable.new; [cv.signal.class, cv.broadcast.class] }
t(:cv_wait_timeout) { m = Mutex.new; cv = ConditionVariable.new; m.synchronize { r = cv.wait(m, 0.02); r.equal?(m) || r } }
t(:mutex_basic) { m = Mutex.new; [m.locked?, m.try_lock, m.locked?, m.owned?, m.try_lock, m.unlock.equal?(m), m.locked?] }
t(:mutex_unlock_err) { Mutex.new.unlock }
t(:mutex_relock) { m = Mutex.new; m.lock; m.lock }
t(:mutex_other_unlock) { m = Mutex.new; m.lock; Thread.new { begin; m.unlock; rescue => e; [e.class, e.message]; end }.value }
t(:mutex_sleep) { m = Mutex.new; m.synchronize { m.sleep(0.01).class } }
t(:mutex_sleep_unlocked) { Mutex.new.sleep(0.01) }
t(:mutex_counter) { m = Mutex.new; c = 0; 10.times.map { Thread.new { 1000.times { m.synchronize { c += 1 } } } }.each(&:join); c }
t(:mutex_sync_ret) { Mutex.new.synchronize { 42 } }
t(:mutex_dead_owner) { m = Mutex.new; Thread.new { m.lock }.join; [m.locked?, m.try_lock] }
t(:value_exc) { th = Thread.new { Thread.current.report_on_exception = false; raise IOError, "io" }; th.value }
t(:join_exc) { th = Thread.new { Thread.current.report_on_exception = false; raise "j" }; th.join }
t(:join_timeout) { th = Thread.new { sleep 1 }; r = th.join(0.01); th.kill; r }
t(:status) { th = Thread.new { Thread.current.report_on_exception = false; raise "x" }; th.join rescue nil; [th.status, th.alive?, Thread.new {}.tap(&:join).status] }
t(:roe_default) { Thread.report_on_exception }
t(:roe_output) { th = Thread.new { raise ArgumentError, "rep" }; sleep 0.01 while th.alive?; th.join rescue $!.message }
t(:deadlock_in_thread) { m = Queue.new; Thread.new { m.pop }.join }
puts "after deadlock"
