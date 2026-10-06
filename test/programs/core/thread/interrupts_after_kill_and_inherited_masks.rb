# An exception sent to a thread while its kill unwinds replaces the
# kill; and a new thread starts under its creator's handle_interrupt
# masks.
def stopped(t) = (Thread.pass until t.stop?)

log = []
t = Thread.new do
  begin
    begin
      sleep
    ensure
      log << Thread.current.status
      sleep
    end
  rescue RuntimeError => e
    log << [:rescued, e.message, Thread.current.status]
  end
  log << :after
  :value
end
stopped(t)
t.kill
Thread.pass until log.size >= 1
stopped(t)
t.raise "wakeup"
p t.value, log

# Masks pass to the threads made inside handle_interrupt.
q = Thread::Queue.new
Thread.handle_interrupt(RuntimeError => :never) do
  done = false
  th = Thread.new do
    q << :started
    Thread.pass until done
    q << Thread.pending_interrupt?
    begin
      Thread.handle_interrupt(RuntimeError => :immediate) {}
    rescue RuntimeError => e
      q << e.message
    end
  end
  q.pop
  th.raise "held"
  done = true
  th.join
  p [q.pop, q.pop]
end

# An inherited :on_blocking mask holds the exception back until the
# thread blocks.
Thread.handle_interrupt(RuntimeError => :on_blocking) do
  inside = Thread::Queue.new
  th = Thread.new do
    begin
      inside << :ready
      x = 0
      200_000.times { x += 1 }
      sleep
    rescue RuntimeError => e
      [:at_sleep, e.message, x]
    end
  end
  inside.pop
  th.raise "blocking"
  p th.value
end

# Outside the block, a new thread has no mask.
th = Thread.new do
  Thread.current.report_on_exception = false
  sleep
end
stopped(th)
th.raise "free"
p(begin
  th.join
rescue RuntimeError => e
  e.message
end)
