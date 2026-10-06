# A select gives up the GVL in ruby, even when its descriptors are ready
# at once: the other threads run, and see the selecting thread asleep.
r, w = IO.pipe

# An exception the mask keeps for a blocking call arrives in the select.
exc = StandardError.new("on blocking")
exc.set_backtrace([])
count = 0
statuses = []
th = Thread.new do
  Thread.handle_interrupt(StandardError => :on_blocking) do
    begin
      IO.select([r], [w])
    rescue StandardError => e
      count += 1
      retry
    end while true
  end
end
200.times do
  Thread.pass until th.stop?
  statuses << th.status
  th.raise(exc)
end
th.kill
th.join
p statuses.uniq
p count >= 199
p th.status

# The same with IO#wait_writable, which waits on one descriptor.
seen = 0
waiter = Thread.new do
  Thread.handle_interrupt(StandardError => :on_blocking) do
    begin
      w.wait_writable
    rescue StandardError
      seen += 1
      retry
    end while true
  end
end
50.times do
  Thread.pass until waiter.stop?
  waiter.raise(exc)
end
waiter.kill
waiter.join
p seen >= 49

# A thread alone selects as before.
p IO.select(nil, [w], nil, 0)&.map(&:size)
p IO.select([r], nil, nil, 0)
