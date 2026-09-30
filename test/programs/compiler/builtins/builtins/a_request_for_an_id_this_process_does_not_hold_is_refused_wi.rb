
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

# Every request for an id this process does not hold is refused, and by the
# BARE errno message -- CRuby's `rb_sys_fail(0)` appends no context.
show("Sys.setuid root") { Process::Sys.setuid(0) }
show("Sys.setgid wheel") { Process::Sys.setgid(0) }
show("Sys.seteuid root") { Process::Sys.seteuid(0) }
show("Sys.setreuid root") { Process::Sys.setreuid(0, 0) }
show("UID.change_privilege root") { Process::UID.change_privilege(0) }
show("UID.grant_privilege root") { Process::UID.grant_privilege(0) }
show("UID.eid= root") { Process::UID.eid = 0 }
show("UID.switch") { Process::UID.switch }
show("UID.switch block") { Process::UID.switch { 1 } }
show("GID.switch") { Process::GID.switch }
# A name that resolves is still refused; a name that does not never gets
# as far as the syscall.
show("Sys.setuid by name") { Process::Sys.setuid("root") }
show("Sys.setuid bad name") { Process::Sys.setuid("nosuchuser__") }
show("Sys.setgid bad name") { Process::Sys.setgid("nosuchgroup__") }

