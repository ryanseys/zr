# Timeout.timeout reaches a thread that waits on a descriptor: the wait
# parks, so the timer thread runs and its raise ends the wait.
require "timeout"
r, w = IO.pipe
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
begin
  Timeout.timeout(0.2) { r.wait_readable }
rescue Timeout::Error => e
  p e.class
end
# Far below the wait with no end, far above a busy host's delay.
p (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) < 10
begin
  Timeout.timeout(0.2) { r.read }
rescue Timeout::Error => e
  p e.class
end

