# A Process::Status dumps its status word and pid as ruby's own ivars,
# and loads back equal to the one that was dumped.
system("exit 3")
s = $?
d = Marshal.dump(s)
p d == Marshal.dump(s), d.sub(/pidi.*\z/m, "")
t = Marshal.load(d)
p t.class, t == s, t.pid == s.pid, t.exitstatus, t.inspect == s.inspect
