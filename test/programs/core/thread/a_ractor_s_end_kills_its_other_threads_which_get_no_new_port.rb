# When a ractor's block ends, ruby kills the ractor's other threads and
# waits for their ensure clauses, before the ractor's value is ready
# (rb_thread_terminate_all). In those clauses the ractor makes no new
# port. A thread that ended with an error before then raises nothing
# here. Thread.list in a ractor lists only the ractor's own threads. The
# ractors tell the main one what happened through its port, which keeps
# the order.
Warning[:experimental] = false
log = Ractor::Port.new

worker = Ractor.new(log) do |out|
  ready = Thread::Queue.new
  Thread.new do
    ready << true
    sleep
  ensure
    begin
      Ractor::Port.new
      out << "a port"
    rescue Ractor::ClosedError => e
      out << "closed: #{e.class}: #{e.message}"
    end
  end
  ready.pop
  :done
end
p worker.value
p log.receive

# Two threads, each in its own sleep; both ensure clauses run before the
# value.
two = Ractor.new(log) do |out|
  ready = Thread::Queue.new
  2.times do |i|
    Thread.new do
      ready << i
      sleep
    ensure
      out << "ensure #{i}"
    end
  end
  2.times { ready.pop }
  :both
end
p two.value
p [log.receive, log.receive].sort

# A thread that already died with an error, and one that already ended:
# neither raises in the ractor's end.
quiet = Ractor.new do
  failed = Thread.new do
    Thread.current.report_on_exception = false
    raise "boom"
  end
  done = Thread.new { :ok }
  [failed, done].each { |t| Thread.pass while t.alive? }
  :quiet
end
p quiet.value

# Thread.list in a ractor: its own threads, never the main ractor's.
counts = Ractor.new do
  ready = Thread::Queue.new
  Thread.new do
    ready << true
    sleep
  end
  ready.pop
  [Thread.list.size, Thread.list.include?(Thread.current)]
end
main_extra = Thread.new { sleep }
Thread.pass until main_extra.status == "sleep"
p counts.value
p [Thread.list.size, Thread.list.include?(Thread.current), Thread.list.include?(main_extra)]
main_extra.kill
main_extra.join

# A port that the ractor made while it ran is closed after its end, and
# the main ractor can still make ports.
ports = Ractor.new { Ractor::Port.new }
port = ports.value
p port.closed?
p Ractor::Port.new.closed?
