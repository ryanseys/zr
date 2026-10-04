# A killed thread is aborting while its ensure clauses run, and a sleep
# there resumes; a frozen thread still runs, and only its locals refuse
# writes.
def dying(&blk) = Thread.new { Thread.current.report_on_exception = false; begin; Thread.current.kill; ensure; blk.call; end }
st = nil
t = dying { st = [Thread.current.status, Thread.current.to_s.include?("aborting")] }
t.join
p st
t = dying { Thread.stop; st = Thread.current.status }
Thread.pass while t.status and t.status != 'sleep'
p t.status
t.wakeup
Thread.pass while t.status and t.status == 'sleep'
t.join
p st
q = Queue.new
t = Thread.new do
  begin
    q.push nil
    sleep
  ensure
    q.push Thread.current.status
  end
end
q.pop
t.kill
t.join
p q.pop
p t.status
t = Thread.new { :done }
t.freeze
p t.frozen?, t.thread_variable_get(:a), t.thread_variable?(:a)
p((t.thread_variable_set(:a, 2) rescue [$!.class, $!.message]))
p((t.send(:[]=, :x, 1) rescue $!.class))
p t.value, t.status
t2 = Thread.new { }
p((t2.thread_variable_get(123) rescue $!.message))
t2.join
