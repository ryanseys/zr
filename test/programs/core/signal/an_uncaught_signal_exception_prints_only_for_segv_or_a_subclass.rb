# An uncaught SignalException ends the process by its signal, with no
# message, unless the signal is SIGSEGV or the exception's class is a
# subclass (as Interrupt is). SignalException.new(0) ends it with
# status 1 and no message.
class MySig < SignalException; end

def run(&block)
  r, w = IO.pipe
  pid = fork do
    r.close
    $stderr.reopen(w)
    block.call
  end
  w.close
  err = r.read
  Process.wait(pid)
  [err.lines.first&.chomp, $?.termsig, $?.exitstatus]
end

p run { raise SignalException.new("TERM") }
p run { raise SignalException.new("SEGV") }
p run { raise MySig.new("TERM") }
p run { raise Interrupt }
p run { raise SignalException.new(0) }
p run { at_exit { raise SignalException.new("USR1") } }
p run { at_exit { raise MySig.new("USR2") } }
