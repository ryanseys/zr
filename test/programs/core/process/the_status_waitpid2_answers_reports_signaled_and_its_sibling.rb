# Process.spawn + Process.waitpid2 + Process::Status.
#
# true and false come from PATH: macOS keeps them only in /usr/bin, and
# Alpine only in /bin.
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

# 4) The boxed status: waitpid2's second element, read by index. Its
#    .exited? and .success? find the Process::Status methods at run time.
r, w = IO.pipe
pid = Process.spawn("true", out: w)
w.close
r.read
result = Process.waitpid2(pid)
got_pid = result[0]
got_st  = result[1]
puts got_pid == pid
puts got_st.exited?
puts got_st.success?

