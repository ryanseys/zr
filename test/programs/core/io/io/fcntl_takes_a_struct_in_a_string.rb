
# IO#fcntl passes a String as the struct a command reads and fills, as a
# file lock does, and refuses a frozen one.
require "fcntl"
require "tmpdir"

Dir.mktmpdir do |dir|
  File.open(File.join(dir, "lock"), "w+") do |f|
    # darwin's struct flock: l_start, l_len, l_pid, l_type, l_whence.
    lock = [0, 0, 0, Fcntl::F_WRLCK, 0].pack("q q i s s")
    p f.fcntl(Fcntl::F_SETLK, lock)
    probe = [0, 0, 0, Fcntl::F_RDLCK, 0].pack("q q i s s")
    p f.fcntl(Fcntl::F_GETLK, probe), probe.unpack("q q i s s")[3] == Fcntl::F_UNLCK
  end
end
p((STDIN.fcntl(Fcntl::F_GETFL, "x".freeze) rescue $!.class))

