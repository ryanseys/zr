# The timeout-gem shape: a thread parked in a LONG sleep is raisable
# and wakes now, not at the sleep's natural end. Threshold-based (well
# under the 10s the sleep would otherwise take), never order-based.

Thread.report_on_exception = false
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
t = Thread.new do
  begin
    sleep 10
    :overslept
  rescue => e
    e.message
  end
end
sleep 0.01 until t.status == "sleep"
t.raise("wake up")
v = t.value
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
p v
p elapsed < 5
