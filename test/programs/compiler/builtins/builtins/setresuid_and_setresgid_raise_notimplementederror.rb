
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

# `setresuid`/`setresgid` are the not-implemented stubs, which take any
# arguments at all and still report arity 0.
show("Sys.setresuid") { Process::Sys.setresuid(0, 0, 0) }
show("Sys.setresgid") { Process::Sys.setresgid }
puts "setresuid arity: #{Process::Sys.method(:setresuid).arity}"

