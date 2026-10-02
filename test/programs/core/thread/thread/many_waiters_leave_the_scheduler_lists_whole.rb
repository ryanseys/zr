# Many threads that wait on one pipe, through wait_readable and
# IO.select, wake when it becomes readable and leave the scheduler's
# lists whole: a later timed wait still times out.
r, w = IO.pipe
n = 200
arrived = Queue.new
threads = Array.new(n) do |i|
  Thread.new do
    arrived << 1
    ready = i.even? ? r.wait_readable(3) : IO.select([r], nil, nil, 3)
    ready ? 1 : 0
  end
end
n.times { arrived.pop }
sleep 0.05
w.write "x"
p threads.sum(&:value)

r2, _w2 = IO.pipe
p r2.wait_readable(0.1)
p IO.select([r2], nil, nil, 0.1)
