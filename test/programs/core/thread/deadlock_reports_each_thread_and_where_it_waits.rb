# A deadlock's error lists the threads: how many sleep, each one with
# its state, the threads that join it, and where it waits.
def frame_for_deadlock_test_1
  yield
end

def frame_for_deadlock_test_2
  yield
end

q = Thread::Queue.new
t = Thread.new { frame_for_deadlock_test_1 { q.pop } }
begin
  frame_for_deadlock_test_2 { t.join }
rescue Exception => e # rubocop:disable Lint/RescueException
  p e.class
  puts e.message.gsub(/0x\h+/, "X").gsub(/native:\S+/, "native:X").gsub(%r{[\w./-]*/(?=\w+\.rb)}, "")
end

