# The first thread to reach a `/#{...}/o` builds it, and a second thread
# that reaches it meanwhile waits and gets the same Regexp (vm_once). zr
# lets each thread build, and the last one stays.
m = Thread::Mutex.new
build = proc { |i| /#{m.unlock; sleep 0.2; i}/o }
results = []
n = 0
first = Thread.new { m.lock; results << build.call(n += 1) }
second = Thread.new { m.lock; results << build.call(n += 1) }
first.join
second.join
p results
