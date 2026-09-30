
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

# Re-asserting the ids the process already holds is the one change it is
# allowed to make, and it answers what CRuby answers: nil from `Sys`, the
# argument as written from `UID`/`GID`.
show("Sys.setuid self") { Process::Sys.setuid(uid) }
show("Sys.setgid self") { Process::Sys.setgid(gid) }
show("Sys.seteuid self") { Process::Sys.seteuid(euid) }
show("Sys.setegid self") { Process::Sys.setegid(egid) }
show("Sys.setruid self") { Process::Sys.setruid(uid) }
show("Sys.setrgid self") { Process::Sys.setrgid(gid) }
show("Sys.setreuid self") { Process::Sys.setreuid(uid, euid) }
show("Sys.setregid self") { Process::Sys.setregid(gid, egid) }
show("UID.change_privilege self") { Process::UID.change_privilege(uid) == uid }
show("GID.change_privilege self") { Process::GID.change_privilege(gid) == gid }
show("UID.grant_privilege self") { Process::UID.grant_privilege(uid) == uid }
show("GID.grant_privilege self") { Process::GID.grant_privilege(gid) == gid }
show("UID.eid= self") { (Process::UID.eid = uid) == uid }
show("GID.eid= self") { (Process::GID.eid = gid) == gid }

