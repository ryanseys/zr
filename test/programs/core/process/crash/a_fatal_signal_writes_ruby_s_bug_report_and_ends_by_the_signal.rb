# A fatal signal (SIGSEGV, SIGBUS, SIGILL or SIGABRT) writes ruby's bug
# report on stderr, and then the signal's default action ends the
# process. The report starts with the place of the running Ruby code and
# the signal, then the ruby's description, then the frames.
SECTIONS = ["-- Control frame information", "-- Ruby level backtrace information",
            "-- Threading information", "-- Other runtime information"].freeze

def crash(signal) = [1].each { Process.kill(signal, $$) }

def report(signal)
  r, w = IO.pipe
  pid = fork do
    r.close
    $stderr.reopen(w)
    crash(signal)
  end
  w.close
  text = r.read
  Process.wait(pid)
  [text, $?]
end

%i[SEGV BUS ILL ABRT].each do |signal|
  text, status = report(signal)
  lines = text.lines(chomp: true)
  puts lines[0].sub(/0x\h{16}/, "0x...")
  p lines[1] == RUBY_DESCRIPTION, lines[2]
  p(lines.select { |line| SECTIONS.any? { line.start_with?(it) } }.map { it[/\A-- (.*?) -+\z/, 1] })
  start = lines.index { it.start_with?("-- Ruby level backtrace information") }
  puts lines[(start + 1)..].take_while { !it.empty? }
  p lines.grep(/\ATotal ractor count|\ARuby thread count/)
  p lines.grep(/\A\* (Loaded script|Ruby Box)/)
  p lines.include?("* Loaded features:")
  p [status.signaled?, status.termsig == Signal.list[signal.to_s], status.exitstatus]
end
