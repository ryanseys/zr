# A spawn's uid: and gid: options take an id or a name; the child sets
# its group, then its user, before its exec. A user may not take
# another's id, and no option may change the ids in a UID.switch block.
require "etc"

def t
  p yield
rescue => e
  p [e.class, e.message]
end

user = Etc.getpwuid(Process.uid).name
group = Etc.getgrgid(Process.gid).name
t { system("true", uid: Process.uid) }
t { system("true", uid: user) }
t { IO.popen(["sh", "-c", "id -u", uid: user], &:read) == "#{Process.uid}\n" }
t { IO.popen(["sh", "-c", "id -g", gid: Process.gid], &:read) == "#{Process.gid}\n" }
t { system("true", gid: group, uid: user) }
if Process.uid.zero?
  puts "nil", "[Errno::EPERM, \"Operation not permitted - true\"]", "nil"
else
  t { system("true", uid: 30000) }
  t { system("true", uid: 30000, exception: true) }
  t { system("true", gid: 30000) }
end
t { system("true", uid: "no such user zr") }
t { system("true", gid: "no such group zr") }
t { system("true", uid: :sym) }
t { system("true", gid: 1.5) }
t { Process::UID.switch { system("true", uid: Process.uid) } }
