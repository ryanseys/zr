# Two threads that run a /.../o site at the same time get one regexp:
# the site keeps a single value, and every later run reads it.
m = Thread::Mutex.new
site = proc { |i| /#{m.unlock; sleep 0.05; i}/o }
got = []
n = 0
threads = 2.times.map { Thread.new { m.lock; got << site.call(n += 1) } }
threads.each(&:join)
p got.size, got[0].equal?(got[1])
p site.call(99).equal?(got[0])
def once_site(x) = /#{x}/o
p [once_site(1), once_site(2)]
p once_site(3).frozen?
