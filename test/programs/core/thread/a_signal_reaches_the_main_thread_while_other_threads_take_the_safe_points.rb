# The main thread runs a signal's command, even when the safe points that
# follow the signal fall in other threads: each new thread here takes the
# first one.
Thread.report_on_exception = false
trap(:TERM) do
  puts "term"
  exit
end
Process.spawn("/bin/sh", "-c", "sleep 0.5; kill -TERM #{Process.pid}")
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
loop do
  t = Thread.new { sleep 0 }
  t.raise Interrupt
  Thread.pass
  abort "no signal after 10 s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 10
end
