require "io/console"
require "pty"

# A terminal whose read needs no byte (min: 0) returns at once, or after
# its time, also while another thread sleeps with a time limit, as the
# timeout library's own thread does after a block ends.
sleeper = Thread.new { sleep 5 }
waiter = Thread.new do
  mutex = Thread::Mutex.new
  mutex.synchronize { Thread::ConditionVariable.new.wait(mutex, 5) }
end
Thread.pass

def elapsed
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  value = yield
  [value, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
end

m, s = PTY.open
value, took = elapsed { s.getch(min: 0) }
p [:min0, value, took < 1]
value, took = elapsed { s.getch(min: 0, time: 0.2) }
p [:min0_time, value, took >= 0.15, took < 2]
value, took = elapsed { s.raw(min: 0) { s.read_nonblock(1, exception: false) } }
p [:nonblock, value, took < 1]
value, = elapsed { s.raw(min: 0, time: 0.1) { s.sysread(1) rescue $!.class } }
p [:sysread, value]

# With min: 1 the read waits for its byte while the other thread runs,
# as test_raw_minchar has it.
main = Thread.current
q = Thread::Queue.new
len = 0
go = false
th = Thread.start do
  q.pop
  sleep 0.01 until main.stop?
  len += 1
  m.print("a")
  m.flush
  sleep 0.01 until go && main.stop?
  len += 10
  m.print("1234567890")
  m.flush
end
sleep 0.1
q.push(1)
p [s.getch(min: 1), len]
go = true
p [s.getch, len]
th.join
p s.read_nonblock(20, exception: false)
m.close
s.close
p [sleeper.alive?, waiter.alive?]
