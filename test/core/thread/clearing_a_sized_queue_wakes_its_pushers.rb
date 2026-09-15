# SizedQueue#clear empties the queue and wakes every thread waiting to
# push, as rb_szqueue_clear does.

q = SizedQueue.new(1)
q << 1
pusher = Thread.new { q << 2; :pushed }
Thread.pass until pusher.status == "sleep"
q.clear
p pusher.value, q.size, q.pop
p Thread::SizedQueue.instance_method(:clear).owner

__END__
:pushed
1
2
Thread::SizedQueue
