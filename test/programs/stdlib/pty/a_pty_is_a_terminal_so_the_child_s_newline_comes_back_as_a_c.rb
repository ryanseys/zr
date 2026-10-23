# pty -- a pseudo-terminal for a child process. A pty IS a terminal, so the
# child's "\n" comes back "\r\n" (ONLCR) -- the observable difference from a
# pipe, and what the golden pins.
require "pty"

p PTY.respond_to?(:spawn)
p PTY.respond_to?(:getpty)
p PTY.respond_to?(:open)
p PTY.respond_to?(:check)

PTY.spawn("printf 'from a pty\n'") do |r, w, pid|
  p r.gets
  p pid.positive?
  w.close
  r.close
end

master, slave = PTY.open
p master.class
p slave.class
p slave.path.start_with?("/dev/")
slave.close
master.close

r, w, pid = PTY.spawn("true")
begin
  # The child exits when it gets to run: check until it has, not once
  # after a fixed time.
  200.times { PTY.check(pid, true); sleep 0.05 }
  p "no raise"
rescue PTY::ChildExited => e
  p e.class
end
w.close
r.close
