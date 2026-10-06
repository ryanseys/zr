# A trap command runs in the main thread, also when another thread sent
# the signal; a join in it works, and a sleep goes on after it.
t0 = Thread.current
t = Thread.new { Thread.pass until t0.stop?; Process.kill(:INT, $$); :normal_end }
ran = []
Signal.trap(:INT) { ran << Thread.current.equal?(Thread.main); ran << t.value }
p t.value
Thread.pass until ran.size == 2
p ran
s = Thread.new { sleep 0.05; Process.kill(:USR1, $$) }
Signal.trap(:USR1) { ran << :usr1 }
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sleep 0.3
p ran.last, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= 0.29
s.join
