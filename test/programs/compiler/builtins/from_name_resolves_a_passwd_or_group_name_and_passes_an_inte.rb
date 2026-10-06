
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

# `from_name` resolves a passwd or group name; an Integer passes straight
# through, and anything that is neither takes the Integer conversion's own
# refusal.
show("UID.from_name root") { Process::UID.from_name("root") }
show("UID.from_name self") { Process::UID.from_name(uid) == uid }
show("GID.from_name self") { Process::GID.from_name(gid) == gid }
show("UID.from_name float") { Process::UID.from_name(1.9) }
show("UID.from_name negative") { Process::UID.from_name(-1) }
show("UID.from_name to_int") do
  o = Object.new
  def o.to_int = 7
  Process::UID.from_name(o)
end
show("UID.from_name bignum") { Process::UID.from_name(2**70) }
show("UID.from_name nil") { Process::UID.from_name(nil) }
show("UID.from_name symbol") { Process::UID.from_name(:root) }
show("UID.from_name missing") { Process::UID.from_name("nosuchuser__") }
show("GID.from_name missing") { Process::GID.from_name("nosuchgroup__") }

