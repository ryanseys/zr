# Two threads wait for children at once: one for a given pid, one for
# any child. One SIGCHLD wakes them both, so each one sees its child.
long_r, long_w = IO.pipe
short_r, short_w = IO.pipe
long_pid = fork { [short_r, short_w, long_w].each(&:close); long_r.read }
short_pid = fork { [long_r, long_w, short_w].each(&:close); short_r.read }
waiter = Thread.new { Process.waitpid(long_pid) }
Thread.pass until waiter.stop?
short_w.close
p Process.waitpid(-1) == short_pid
waiter.kill
waiter.join

any = Thread.new do
  Process.waitpid(-1)
rescue Errno::ECHILD
  nil
end
Thread.pass until any.stop?
given = Thread.new do
  Process.waitpid(long_pid)
rescue Errno::ECHILD
  nil
end
Thread.pass until given.stop?
long_w.close
p [any, given].map(&:value).compact == [long_pid]
