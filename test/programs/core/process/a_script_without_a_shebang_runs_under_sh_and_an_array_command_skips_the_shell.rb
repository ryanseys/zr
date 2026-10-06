# A spawned script with no #! line runs under /bin/sh, as execve's ENOEXEC
# retries it; a popen Array of one word runs no shell; file redirects
# take their flags and permissions.
require "tmpdir"
def t
  r = yield
  p r
rescue => e
  p [e.class, e.message]
end
Dir.chdir(Dir.mktmpdir)
t { IO.popen([{ "A" => "B" }, "env", unsetenv_others: true], &:read) }
t { IO.popen(["echo bar"]) {} }
t { Process.wait Process.spawn("echo", "a", STDOUT => ["out", File::WRONLY | File::CREAT | File::TRUNC, 0o644]); File.read("out") }
t { Process.wait Process.spawn("echo", "0", STDOUT => ["out", File::WRONLY | File::CREAT | File::APPEND, 0o644]); File.read("out") }
t { Process.wait Process.spawn("sort", STDIN => ["out", File::RDONLY, 0o644], STDOUT => ["out2", File::WRONLY | File::CREAT | File::TRUNC, 0o644]); File.read("out2") }
t { Process.wait Process.spawn("echo", "b", [STDOUT, STDERR] => ["out", File::WRONLY | File::CREAT | File::TRUNC, 0o644]); File.read("out") }
t { Process.wait Process.spawn("echo", "c", STDERR => STDOUT, STDOUT => ["out", File::WRONLY | File::CREAT | File::TRUNC, 0o644]); File.read("out") }
File.write("tmp_script.cmd", ": ;\n", perm: 0o755)
t { pid = Process.spawn({ "PATH" => Dir.pwd }, "tmp_script.cmd"); Process.waitpid2(pid)[1].success? }
t { system(["true", "true"]) }
