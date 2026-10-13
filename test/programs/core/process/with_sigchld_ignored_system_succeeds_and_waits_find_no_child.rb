# When a program ignores SIGCHLD, the system reaps each child itself.
# `system` then returns true with a status of pid -1 and exit 0, as
# rb_process_status_wait makes one. A wait for the child finds none.
def outcome
  yield
rescue => e
  [e.class, e.message]
end

p Signal.trap(:CHLD, "IGNORE")
p system("true")
p [$?.class, $?.pid, $?.exitstatus, $?.success?, $?.to_s, $?.inspect, $?.frozen?]

# The exit status of the child is lost, so a failure looks like success.
p system("exit 3")
p $?
p system("exit 3", exception: true)

# Backticks and IO.popen give the output, and leave `$?` cleared.
p `echo hi`
p $?
p IO.popen("echo pop") { |io| io.read }
p $?

# A wait raises ECHILD and leaves `$?` as it was.
system("true")
pid = spawn("true")
p outcome { Process.wait(pid) }
p $?
p outcome { Process.wait2(spawn("true")) }
p outcome { Process.waitpid(spawn("true")) }
p Process.waitall
p Process::Status.wait(spawn("true"))
p Process.detach(spawn("true")).value

# A command that does not start leaves `$?` cleared after system, and
# unchanged after spawn.
p system("zr-test-no-such-command")
p $?
system("true")
p outcome { spawn("zr-test-no-such-command") }
p $?

# SIG_IGN and nil ignore SIGCHLD too.
p Signal.trap(:CHLD, "SIG_IGN")
p [system("exit 4"), $?.pid]
p Signal.trap(:CHLD, nil)
p [system("exit 4"), $?.pid]

# Any other handling lets ruby wait for the child again.
p Signal.trap(:CHLD, "DEFAULT")
p [system("exit 3"), $?.exitstatus, $?.pid.positive?]
p [system("zr-test-no-such-command"), $?.exitstatus]
Signal.trap(:CHLD, "SYSTEM_DEFAULT")
p [system("exit 5"), $?.exitstatus]
Signal.trap(:CHLD) { }
p [system("exit 6"), $?.exitstatus]
Signal.trap(:CHLD, "DEFAULT")
p outcome { system("exit 7", exception: true) }
