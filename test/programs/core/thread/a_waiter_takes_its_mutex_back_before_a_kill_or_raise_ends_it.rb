# A thread in ConditionVariable#wait or Mutex#sleep takes its mutex back
# before a kill or an exception that another thread sent ends the wait,
# as mutex_lock_uninterruptible does. So its ensure owns the mutex, and
# the synchronize around it unlocks it.
def run_case(label, how)
  m = Mutex.new
  cv = ConditionVariable.new
  in_sync = false
  seen = []
  th = Thread.new do
    Thread.current.report_on_exception = false
    m.synchronize do
      in_sync = true
      begin
        how == :sleep ? m.sleep : cv.wait(m)
        seen << :returned
      rescue => e
        seen << e.class
      ensure
        seen << m.owned?
      end
    end
    seen << m.locked?
  end
  Thread.pass until in_sync
  Thread.pass until th.stop?
  m.synchronize do
    how == :sleep ? th.wakeup : cv.signal
    sleep 0.001
    label == :kill ? th.kill : th.raise(ArgumentError)
    seen << th.status
  end
  th.join
  p [how, label, seen, th.status, m.locked?]
end

%i[wait sleep].each do |how|
  run_case(:kill, how)
  run_case(:raise, how)
end
