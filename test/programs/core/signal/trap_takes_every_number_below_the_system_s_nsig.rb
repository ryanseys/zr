# trap takes any number below the system's NSIG: 32 on macOS, 65 on
# Linux, where the real-time signals have no name. The system may keep
# some of them for itself, and trap then raises EINVAL with the number.
# Each line holds on every system.
def outcome
  yield
rescue => e
  [e.class, e.message]
end

# NSIG is the largest number that SignalException takes.
nsig = (1..1024).find { |n| outcome { SignalException.new(n) }.is_a?(Array) } - 1
p SignalException.new(nsig).signo == nsig
p outcome { SignalException.new(nsig + 1) } == [ArgumentError, "invalid signal number (#{nsig + 1})"]

# trap refuses NSIG and above, and below zero.
p outcome { Signal.trap(nsig, "DEFAULT") } == [ArgumentError, "invalid signal number (#{nsig})"]
p outcome { Signal.trap(nsig + 100) { } } == [ArgumentError, "invalid signal number (#{nsig + 100})"]
p outcome { Signal.trap(-1, "DEFAULT") }

# Each number below NSIG without a name gets the system's own handling,
# or EINVAL that names it as SIG and its number.
unnamed = (1...nsig).reject { |n| Signal.signame(n) }
outcomes = unnamed.to_h { |n| [n, outcome { Signal.trap(n, "SYSTEM_DEFAULT") }] }
p(outcomes.all? { |n, r| r == "SYSTEM_DEFAULT" || r == [Errno::EINVAL, "Invalid argument - SIG#{n}"] })
p unnamed.all? { |n| SignalException.new(n).message == "SIG#{n}" }

# A free one runs its handler, as a named one does.
free = outcomes.key("SYSTEM_DEFAULT")
handled = lambda do |signo|
  got = []
  Signal.trap(signo) { |number| got << number }
  Process.kill(signo, Process.pid)
  50.times { break unless got.empty?; sleep 0.02 }
  Signal.trap(signo, "SYSTEM_DEFAULT")
  got == [signo]
end
p handled.(Signal.list.fetch("USR1"))
p(free.nil? || handled.(free))

# A child that a signal ends shows its name and number, or its number
# alone when the signal has no name.
def ended_by(signo)
  pid = spawn("kill -#{signo} $$")
  Process.wait(pid)
  [$?.signaled?, $?.termsig == signo, $?.to_s.sub(/\Apid \d+ /, "")]
end
p ended_by(Signal.list.fetch("TERM"))
p(free.nil? || ended_by(free) == [true, true, "signal #{free}"])
p(free.nil? || Process.last_status.inspect.match?(/\A#<Process::Status: pid \d+ signal #{free}>\z/))
