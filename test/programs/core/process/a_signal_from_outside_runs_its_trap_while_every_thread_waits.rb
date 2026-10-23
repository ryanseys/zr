# Each child process sends a signal while every thread of this one waits;
# the trap runs at once, not when a thread next wakes.
def from_outside(signal, delay = 0.2)
  Process.spawn("/bin/sh", "-c", "sleep #{delay}; kill -#{signal} #{Process.pid}")
end

def timed
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  # A bound that only a trap that never ran can pass, not a slow runner.
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 30
end

# A sleep with no end.
trap(:USR1) { raise "usr1" }
p(timed do
  from_outside(:USR1)
  sleep
rescue RuntimeError => e
  p e.message
end)

# Another thread sleeps longer.
p(timed do
  t = Thread.new { sleep 10 }
  from_outside(:USR1)
  sleep
rescue RuntimeError => e
  p e.message
  t.kill
end)

# The main thread joins a thread that sleeps.
p(timed do
  t = Thread.new { sleep 10 }
  from_outside(:USR1)
  t.join
rescue RuntimeError => e
  p e.message
  t.kill
end)

# The main thread reads a pipe with nothing in it.
p(timed do
  r, w = IO.pipe
  from_outside(:USR1)
  r.read(1)
rescue RuntimeError => e
  p e.message
  [r, w].each(&:close)
end)

# A trap that only records lets the sleep go on until its end.
got = []
trap(:USR2) { got << :usr2 }
p(timed do
  pid = from_outside(:USR2, 0.1)
  sleep 1
  # The child may start late: its signal is sent once it has exited.
  Process.wait(pid)
  sleep 0.01 while got.empty?
end)
p got

# A trap that exits ends the program from an endless sleep.
trap(:TERM) { puts "term"; exit 0 }
from_outside(:TERM)
loop { sleep }
