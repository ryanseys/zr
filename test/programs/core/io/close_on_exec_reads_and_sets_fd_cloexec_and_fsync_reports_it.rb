# close_on_exec reads and sets FD_CLOEXEC on the descriptor; fsync and
# fdatasync report the call's error.
path = "/tmp/zr_spec_cloexec.txt"
File.write(path, "x")
p [STDOUT.close_on_exec?, STDIN.close_on_exec?, STDERR.close_on_exec?, File.open(path, &:close_on_exec?)]
r, w = IO.pipe
before = r.close_on_exec?
r.close_on_exec = false
p [before, r.close_on_exec?, r.fcntl(1)]
# A pipe has no fsync: EINVAL on Linux and macOS 27, ENOTSUP on macOS 15.
p((w.fsync rescue $!.is_a?(SystemCallError)), (w.fdatasync rescue $!.is_a?(SystemCallError)))
File.open(path, "w") { |f| p f.fsync }
File.delete(path)
