# Process.spawn + Process.waitpid2 + Process::Status.
#
# true/false are spelled /usr/bin/... because that is where macOS keeps them;
# /bin/true and /bin/false do not exist there, and spawning them raised an
# uncaught Errno::ENOENT part way through this file. Both paths exist on Linux.
#
# CRuby semantics:
#   Process.spawn(cmd, *args, opts) -> Integer pid
#   Process.waitpid2(pid) -> [pid, Process::Status]
#   Process::Status#signaled?   -> true if killed by signal
#   Process::Status#exited?     -> true if exited normally
#   Process::Status#exitstatus  -> exit code (0..255) or nil
#   Process::Status#termsig     -> signal number or nil
#   Process::Status#coredump?   -> true if dumped core
#   Process::Status#success?    -> true if exited? and exitstatus == 0
#   Process::Status#pid         -> pid
#
# Process::Status has no public constructor in CRuby: the only way to
# obtain one is Process.waitpid2 on a real subprocess. Other tests check
# `status.exitstatus == 0`. This one checks the four members that a
# signal check in a shell tool uses: exited?, success?, signaled?, pid.

# 1) Normal exit, success path. /bin/echo exits 0.
r, w = IO.pipe
pid = Process.spawn("/bin/echo", "-n", "hello", out: w)
w.close
out = r.read
_, status = Process.waitpid2(pid)
puts out == "hello"               # the spawned process actually ran
puts status.exited?               # exited normally
puts status.success?              # exited 0
puts status.signaled? == false    # not killed by signal
# status.pid is tested in (4), through the pair that waitpid2 gives.

