
# `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
#
# Every id printed here is compared against one the process already knows,
# never printed raw, so the output is the same on any machine. Nothing in
# this file can change an id: an unprivileged process may only re-assert the
# ids it already holds, and every other request is refused.

uid = Process.uid
euid = Process.euid
gid = Process.gid
egid = Process.egid

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{label}: #{e.class}: #{e.message}"
end

# The readers, each against the answer `Process` already gives.
show("Sys.getuid") { Process::Sys.getuid == uid }
show("Sys.geteuid") { Process::Sys.geteuid == euid }
show("Sys.getgid") { Process::Sys.getgid == gid }
show("Sys.getegid") { Process::Sys.getegid == egid }
show("Sys.issetugid") { Process::Sys.issetugid }
show("UID.rid") { Process::UID.rid == uid }
show("UID.eid") { Process::UID.eid == euid }
show("GID.rid") { Process::GID.rid == gid }
show("GID.eid") { Process::GID.eid == egid }
show("UID.sid_available?") { Process::UID.sid_available? }
show("GID.sid_available?") { Process::GID.sid_available? }

