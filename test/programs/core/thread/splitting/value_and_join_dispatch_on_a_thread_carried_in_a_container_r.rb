# A Thread carried through a container: #value/#join answer the thread's
# result, not nil.
ts = (1..3).map { |i| Thread.new { i * 10 } }
p ts.map { |t| t.value }
p ts[0].value            # idempotent: re-reading a finished thread's value
arr = [Thread.new { 99 }]
p arr[0].value
m = Mutex.new
n = 0
m.synchronize { n += 1 }
puts n
