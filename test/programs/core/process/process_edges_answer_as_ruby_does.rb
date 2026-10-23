def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

t(:spawn) { pid = spawn("echo", "hi", out: File::NULL); Process.wait(pid); $?.success? }
t(:backtick) { [`echo a`, $?.exitstatus, `exit 3`, $?.exitstatus, $?.inspect.sub(/pid \d+/, "pid N")] }
t(:system) { [system("true"), system("false"), system("nonexistent_cmd_zz"), system("exit 2"), $?.exitstatus] }
t(:popen) { IO.popen(["cat"], "r+") { |io| io.write("x"); io.close_write; io.read } }
t(:popen_env) { IO.popen({"ZZ" => "q"}, "echo $ZZ", &:read) }
t(:fork) { r, w = IO.pipe; pid = fork { r.close; w.write("child"); exit!(4) }; w.close; Process.wait(pid); [r.read, $?.exitstatus] }
t(:fork_status) { pid = fork { Process.kill(:TERM, Process.pid) }; Process.wait(pid); [$?.signaled?, $?.termsig, $?.to_s.sub(/\d+/, "N")] }
t(:wait2) { pid = spawn("sh", "-c", "exit 7"); Process.wait2(pid)[1].exitstatus }
# A child that cannot have exited yet, however late the wait comes.
t(:waitpid_nohang) { pid = spawn("sleep", "30"); r = Process.waitpid(pid, Process::WNOHANG); Process.kill(:KILL, pid); Process.wait(pid); r }
t(:detach) { pid = spawn("true"); Process.detach(pid).value.class }
t(:redirect) { r, w = IO.pipe; pid = spawn("sh", "-c", "echo err >&2", err: w); w.close; Process.wait(pid); r.read }
t(:redirect2) { r, w = IO.pipe; pid = spawn("sh -c 'echo o; echo e >&2'", [:out, :err] => w); w.close; Process.wait(pid); r.read }
t(:chdir) { IO.popen(["pwd"], chdir: "/") { _1.read } }
t(:umask_spawn) { IO.popen(["sh", "-c", "umask"], umask: 0o077, &:read) }
t(:rlimit) { Process.getrlimit(:NOFILE).all?(Integer) }
t(:clock) { [Process.clock_gettime(Process::CLOCK_MONOTONIC).class, Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond).class, Process.clock_getres(:CLOCK_MONOTONIC).class, Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID).class] }
t(:times) { Process.times.class }
t(:trap) { r = []; old = trap("USR1") { r << :got }; Process.kill(:USR1, Process.pid); sleep 0.05; trap("USR1", old); r }
t(:trap_ign) { trap("USR2", "IGNORE"); Process.kill(:USR2, $$); sleep 0.01; :alive }
t(:trap_list) { Signal.list.slice("INT", "KILL", "EXIT") }
t(:signame) { Signal.signame(15) }
t(:trap_exit) { trap("EXIT") { } ; :ok }
t(:kill_bad) { Process.kill(:NOPE, $$) }
t(:interrupt) { begin; Process.kill(:INT, $$); sleep 0.1; rescue Interrupt => e; e.message; end }
t(:open3) { require "open3"; o, e, s = Open3.capture3("sh", "-c", "echo out; echo err >&2; exit 1"); [o, e, s.exitstatus] }
t(:open3_pipe) { require "open3"; Open3.pipeline_r("echo abc", "tr a-z A-Z") { |o, ts| o.read } }
t(:exec_fail) { pid = fork { exec("nonexistent_zz") rescue (puts $!.class; exit!(9)) }; Process.wait(pid); $?.exitstatus }
t(:pgid) { Process.getpgid(0).is_a?(Integer) }
t(:euid) { [Process.euid == Process.uid, Process::Status.wait(spawn("true")).class] }
t(:daemon) { Process.respond_to?(:daemon) }
t(:warmup) { Process.warmup }
t(:argv0) { [$0, $PROGRAM_NAME, __FILE__, __dir__.class] }
t(:setproctitle) { Process.setproctitle("zz") }
t(:last_status) { system("exit 5"); Process.last_status.exitstatus }
t(:pty) { require "pty"; PTY.spawn("echo ptyout") { |r, w, pid| [r.gets, Process.wait(pid).class] } }
