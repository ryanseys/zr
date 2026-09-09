# native only: child processes come from libSystem
p system("true"), $?.class, $?.success?, $?.exitstatus, $?.exited?, $?.signaled?, $?.termsig, $?.to_i, $?.pid > 0, $?.inspect.start_with?("#<Process::Status: pid "), $?.inspect.end_with?(" exit 0>"), $?.to_s.end_with?(" exit 0"), $? == 0, $?.stopped?, $?.coredump?
p system("false"), $?.success?, $?.exitstatus, $?.to_i, $? == 256, $?.inspect.end_with?(" exit 1>")
p system("exit 3"), $?.exitstatus, system("echo hi"), system("echo", "a b", "c"), system("printf '%s|' one two"), system("/usr/bin/true"), system("no-such-command-zzz"), $?.exitstatus, $?.class, $?.success?, system("no-such-command-zzz 2>/dev/null"), $?.exitstatus, system("sh", "-c", "exit 7"), $?.exitstatus
p `echo hello`, `printf 'a\nb'`, `echo hello`.encoding, $?.success?, `exit 2`, $?.exitstatus, `printf ''`, `printf ''`.class, `echo ünï`, `echo ünï`.size, `echo 'x'; exit 5`, $?.exitstatus, `echo one
echo two`, %x(echo paren), %x[echo bracket #{1 + 1}], `echo #{"interp"}`
x = "quoted"
p `echo "#{x} #{x.size}"`, `echo $HOME`.empty?, `echo $((6*7))`, `echo hello | tr a-z A-Z`, `cat /dev/null`, `echo -n no-newline`, `printf 'x\\0y'`.bytes, `head -c 70000 /dev/zero`.bytesize, `echo >&2 to-stderr; echo out`, `sh -c 'exit 9'`, $?.exitstatus
begin
  `no-such-command-zzz-bt 2>/dev/null`
  p $?.exitstatus
rescue => e
  p e.class
end
pid = Process.spawn("exit 4")
p pid.class, pid > 0, Process.wait(pid) == pid, $?.exitstatus, $?.pid == pid
pid = Process.spawn("echo spawned")
_, status = Process.wait2(pid)
p status.class, status.exitstatus, status.success?, status.pid == pid, Process.last_status.equal?($?), Process.last_status.equal?(status)
pid = Process.spawn("sh", "-c", "exit 6")
Process.wait(pid)
p $?.exitstatus, Process.pid > 0, Process.ppid > 0, Process.pid != Process.ppid
p Process.wait(Process.spawn("kill -9 $$")).class, $?.signaled?, $?.termsig, $?.exitstatus, $?.success?, $?.exited?, $?.inspect.end_with?(" SIGKILL (signal 9)>"), $?.to_i
p system("kill -15 $$"), $?.termsig, $?.signaled?, system("kill -TERM $$"), $?.termsig
p system("echo", "with", "args"), system("echo with args"), system(""), $?.success?, (system(nil) rescue $!.class), (system("true", 1) rescue $!.class), (system rescue $!.class), (Process.wait rescue $!.class), (Process.wait(999999) rescue $!.class), (Process.wait(999999) rescue $!.message)
p `true`, `false`, $?.exitstatus, (`no-such-command-zzz 2>&1`.empty?), $?.exitstatus, `echo "  spaced  "`, `echo trailing   `, `printf 'no newline'`, `printf '%s\n%s\n' l1 l2`.lines, `echo done`.chomp
at_exit { p :exited, `echo at_exit`.chomp }
