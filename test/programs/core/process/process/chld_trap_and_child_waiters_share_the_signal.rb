# A CHLD trap still runs while threads wait for children, and system
# and backticks let other threads run; trap answers DEFAULT for the
# handling the waiters install.
got = 0
Signal.trap("CHLD") { got += 1 }
t = Thread.new { sleep 0.05; :slept }
pid = spawn("sleep 0.1")
Process.wait(pid)
p t.value, got >= 1
p Signal.trap("CHLD", "DEFAULT").class
ticks = 0
t2 = Thread.new { 20.times { sleep 0.01; ticks += 1 } }
p system("sleep 0.15"), `echo hi`
p ticks >= 5
t2.join
p Signal.trap("CHLD", "DEFAULT")

