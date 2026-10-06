# handle_interrupt masks hold back an exception that a thread raises on
# itself and the main thread's signal exceptions; :on_blocking lets one
# through at a blocking call: a sleep or a write.
$stdout.sync = true

# A raise on itself waits for the block's end under :never.
log = []
begin
  Thread.handle_interrupt(RuntimeError => :never) do
    Thread.current.raise "self"
    log << :went_on
  end
rescue RuntimeError => e
  log << e.message
end
p log

# Without a mask it arrives at once.
p(begin
  Thread.current.raise "now"
  :not_here
rescue RuntimeError => e
  e.message
end)

# :on_blocking holds it until the sleep.
r = nil
q = Thread::Queue.new
e = Class.new(Exception)
main = Thread.current
th = Thread.new do
  Thread.handle_interrupt(Object => :on_blocking) do
    begin
      q.pop
      Thread.current.raise RuntimeError, "in sleep"
      r = :ok
      sleep
    ensure
      main.raise e, "from ensure"
    end
  end
rescue RuntimeError => x
  [:thread, x.message]
end
begin
  q << true
  th.join
rescue e => x
  p [:main, x.message]
end
p r, th.value

# ... or until a write.
waiting = true
started = Thread::Queue.new
t = Thread.new do
  Thread.current.report_on_exception = false
  Thread.handle_interrupt(RuntimeError => :on_blocking) do
    started << true
    nil while waiting
    puts "not written"
  end
end
started.pop
t.raise RuntimeError, "before the write"
waiting = false
p(begin
  t.join
rescue RuntimeError => x
  x.message
end)

# SIGINT's Interrupt waits for the end of a :never block.
inner = false
waiting = Thread::Queue.new
release = Thread::Queue.new
Thread.new do
  waiting.pop
  Process.kill(:INT, Process.pid)
  release << true
end
begin
  Thread.handle_interrupt(SignalException => :never) do
    waiting << true
    release.pop
  rescue Interrupt
    inner = true
    raise
  end
rescue Interrupt
  puts "outer"
end
p inner

# Without a mask SIGINT arrives where the main thread waits.
begin
  Thread.new { Process.kill(:INT, Process.pid) }
  sleep
rescue Interrupt => x
  p x.class
end

# ... but `p` is uninterruptible, so it is no blocking point.
waiting = true
started = Thread::Queue.new
t = Thread.new do
  Thread.current.report_on_exception = false
  Thread.handle_interrupt(RuntimeError => :on_blocking) do
    started << true
    nil while waiting
    p :written
    p :written_too
  end
end
started.pop
t.raise RuntimeError, "after p"
waiting = false
p(begin
  t.join
  :no_raise
rescue RuntimeError => x
  x.message
end)
