# thread_start_func_2 fires these from the VM and not from a frame,
# so the row names no file, no line and no method; `self` is the
# thread the events are for, which is the thread that runs the
# handler. A point enabled with no target_thread watches every
# thread, and one enabled without that watches only its own -- so
# the events of a thread it started would reach it otherwise.
seen = Queue.new
tp = TracePoint.new(:thread_begin, :thread_end) do |t|
  seen << [t.event, t.self.class.to_s, t.self.equal?(Thread.current), t.path, t.lineno,
           t.method_id, t.defined_class, t.binding, t.parameters]
end
tp.enable(target_thread: nil)
Thread.new { 1 }.join
tp.disable
p seen.pop until seen.empty?
