# The exception of a signal's default handler (Interrupt for SIGINT,
# SignalException for the others) rises in the main thread where the
# signal interrupted it: its backtrace starts there, with no frame of the
# code that delivers it. A handle_interrupt mask holds it back until the
# block ends.
def wait_for(signal)
  # The signal comes once the main thread waits, so it rises there.
  Thread.new { Thread.pass until Thread.main.stop?; Process.kill(signal, $$) }
  sleep
rescue SignalException => e
  [e.class, e.message, e.backtrace_locations.first(2).map(&:label)]
end

p wait_for(:INT)
p wait_for(:USR1)
p wait_for(:TERM)

q = Thread::Queue.new
begin
  Thread.new { Thread.pass until Thread.main.stop?; Process.kill(:USR2, $$) }
  q.pop
rescue SignalException => e
  p [e.class, e.message, e.backtrace_locations.first.label]
end

begin
  Thread.handle_interrupt(SignalException => :never) do
    # The block waits until the signal is sent, so it holds it back.
    sent = Thread::Queue.new
    Thread.new { Process.kill(:HUP, $$); sent << true }
    sent.pop
    puts "held back"
  end
rescue SignalException => e
  p [e.class, e.message, e.backtrace_locations.first.label]
end
