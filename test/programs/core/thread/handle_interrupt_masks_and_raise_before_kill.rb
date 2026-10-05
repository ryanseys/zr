def make(config, blocking = true)
  klass = Class.new(RuntimeError)
  rec = []
  inq = Queue.new
  cont = Queue.new
  t = Thread.new do
    begin
      Thread.handle_interrupt(config) do
        begin
          inq << true
          if blocking
            Thread.pass
            cont.pop
          else
            begin
              cont.pop(true)
            rescue ThreadError
              Thread.pass
              retry
            end
          end
        rescue klass
          rec << :interrupted
        end
      end
    rescue klass
      rec << :deferred
    end
  end
  inq.pop
  Thread.pass until t.stop? if blocking
  t.raise klass, "interrupt"
  cont << true
  t.join
  rec
end
p make(RuntimeError => :never), make(RuntimeError => :on_blocking), make({ RuntimeError => :on_blocking }, false), make(RuntimeError => :immediate)
Thread.handle_interrupt(RuntimeError => :never) do
  cur = Thread.current
  Thread.new { cur.raise "interrupt immediate" }.join
  p Thread.pending_interrupt?
  begin
    Thread.handle_interrupt(RuntimeError => :immediate) { p :not_reached }
  rescue => e
    p e.message
  end
  p Thread.pending_interrupt?
end
t = Thread.new { Thread.current.report_on_exception = false; sleep }
Thread.pass until t.stop?
t.raise RuntimeError, "before kill"
t.kill
Thread.pass while t.alive?
p((t.join rescue $!))
