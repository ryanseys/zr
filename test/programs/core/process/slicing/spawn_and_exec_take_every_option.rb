# The spawn options posix_spawn cannot carry go through fork and execve:
# umask, pgroup and rlimit_*. exec takes an environment and options,
# every refusal names what rb_execarg_addopt names, and open("|cmd")
# names a file, as ruby 4.0 reads it.
p system("sh", "-c", "umask", umask: 0o077)
r, w = IO.pipe
pid = spawn("sh", "-c", "read x", pgroup: true, in: r)
r.close
p Process.getpgid(pid) == pid
w.close
Process.wait(pid)
p IO.popen(["sh", "-c", "ulimit -n"], rlimit_nofile: 100, &:read)
p IO.popen(["sh", "-c", "ulimit -c"], rlimit_core: [0, 0], &:read)
p IO.popen(["sh", "-c", "echo $FOO-$HOME"], unsetenv_others: true, &:read)
p IO.popen([{"FOO" => "bar"}, "sh", "-c", "echo $FOO"], &:read)
[-> { spawn("true", new_pgroup: true) }, -> { spawn("true", pgroup: -1) }, -> { spawn("true", umask: "x") },
 -> { spawn("true", rlimit_bogus: 1) }, -> { spawn("true", rlimit_core: [1, 2, 3]) }, -> { spawn("definitely_not_zz") },
 -> { spawn("definitely_not_zz", umask: 0) }, -> { system("definitely_not_zz", exception: true) }].each do |bad|
  p bad.call
rescue => e
  p e
end
p system("definitely_not_zz"), $?.exitstatus
pid = fork { exec({"GREETING" => "hi"}, "sh", "-c", "echo $GREETING-$(pwd)", chdir: "/", umask: 0o22) }
Process.wait(pid)
pid = fork { exec("sh", "-c", "echo to-err >&2", err: :out) }
Process.wait(pid)
p (open("|echo hi") rescue $!.class)

