# A thread that waits for a descriptor wakes when it is ready, also while
# other threads keep the scheduler busy and never all wait at once.
r, w = IO.pipe
stop = false
busy = Array.new(3) do
  Thread.new do
    n = 0
    n += 1 until stop
    n
  end
end
reader = Thread.new { r.read(5) }
Thread.new do
  sleep 0.05
  w.write("hello")
end
p reader.value
child = spawn("true")
p Process.wait(child) == child
stop = true
p busy.map(&:value).all?(&:positive?)
