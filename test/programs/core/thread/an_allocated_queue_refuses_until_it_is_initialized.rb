# ruby 4.1 checks that a Queue or SizedQueue was initialized in each
# method but closed?, before it checks the closed flag: Queue#close sets
# the flag first, SizedQueue#close checks first.
def t; p yield; rescue => e; p [e.class, e.message.sub(/0x\h+/, "X")]; end
q = Thread::SizedQueue.allocate
%i[max size length empty? num_waiting close closed? clear].each { |m| t { [m, q.send(m)] } }
t { q.max = 3 }
t { q.max = 0 }
t { q.push(1) }
qq = Thread::Queue.allocate
%i[size empty? num_waiting close closed? clear].each { |m| t { [m, qq.send(m)] } }
t { qq.push(1) }
r = Thread::SizedQueue.new(2)
t { [r.max, r.num_waiting, r.close.closed?, r.close.closed?] }
s = Thread::Queue.new([1])
t { [s.num_waiting, s.close.closed?, s.close.closed?, s.pop, s.pop] }
