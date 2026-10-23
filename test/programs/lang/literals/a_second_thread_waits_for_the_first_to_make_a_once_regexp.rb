# The first thread to reach a `/#{...}/o` makes it, and a second thread
# that reaches it meanwhile waits and gets the same Regexp (vm_once).
m = Thread::Mutex.new
build = proc { |i| /#{m.unlock; sleep 0.2; i}/o }
results = []
n = 0
first = Thread.new { m.lock; results << build.call(n += 1) }
second = Thread.new { m.lock; results << build.call(n += 1) }
first.join
second.join
p results

# The maker sleeps while another thread waits.
making = Thread::Queue.new
slow = proc { |i| /#{making << i; sleep 0.1; i}/o }
a = Thread.new { slow.call(1) }
making.pop # the first thread is in the interpolation
b = Thread.new { slow.call(2) }
p a.value, b.value, a.value.equal?(b.value)

# A throw out of the interpolation leaves the site unmade, so the next
# run makes it.
escape = proc { |i| catch(:out) { /#{throw :out, i}/o } }
p escape.call(1), escape.call(2)
once = proc { |i| /#{i}/o }
p once.call(3), once.call(4), Thread.new { once.call(5) }.value

# A raise in the interpolation leaves it unmade too, in another thread.
raising = proc { |i| /#{raise "no" if i == 1; i}/o }
failed = Thread.new { Thread.current.report_on_exception = false; raising.call(1) }
p((failed.join rescue $!.message))
p raising.call(2), Thread.new { raising.call(3) }.value
