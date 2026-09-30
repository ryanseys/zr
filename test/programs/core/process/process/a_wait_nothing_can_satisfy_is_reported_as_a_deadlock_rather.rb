# Every blocking primitive registers with the deadlock detector and parks in
# slices, so none of them can hang where CRuby raises.
#
# Before this, exactly ONE of six waits registered -- `Queue#pop`, which is
# why `a_deadlocked_wait_raises_fatal.rb` passed while `Mutex#lock`,
# `SizedQueue#push` back-pressure, `Thread.stop`, `Thread#join` and both
# Ractor receive sites parked untimed and forever. Registration is now a
# property of the wait primitive rather than something each site remembers.
#
# Two of these are not deadlock verdicts at all, and saying so is the point:
# `Thread.stop` with no other thread is CRuby's `rb_thread_alone()`
# ThreadError, decided BEFORE parking, and joining yourself is a ThreadError
# because there is nobody left to finish the thread being waited on.
#
# DIVERGENCE, recorded rather than fixed: for a mutex deadlock CRuby's
# verdict surfaces in the MAIN thread's `join` frame, while zr's surfaces
# in the blocked thread's own `Mutex#lock` -- whichever poll comes first.
# The exception, its class and its message agree; only the frame that
# reports it differs, so the rows below read the class and message and the
# mutex row is not here.

def attempt(name)
  r = begin
    yield.inspect
  rescue Exception => e
    # The first line only: CRuby's `fatal` continues with a thread dump of
    # native addresses that no other implementation can produce.
    "#{e.class}: #{e.message.lines.first.chomp}"
  end
  puts "#{name}\t#{r}"
end

# --- Real verdicts --------------------------------------------------------
attempt("sized queue back-pressure") do
  q = SizedQueue.new(1)
  q << 1
  q << 2
end

