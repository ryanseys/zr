# SignalException and Interrupt: a number takes a message, and a nil
# message gives the class's name; the number survives Marshal; a number
# that is no int, or a name that is not ASCII-compatible, is refused.
p SignalException.new(2, nil).message, SignalException.new(2).message, SignalException.new(15, "bye").message
p Interrupt.new(nil).message, Interrupt.new.message, Interrupt.new("stop").message, Interrupt.new.signo
p SignalException.new("TERM").message, SignalException.new(:SIGHUP).message, SignalException.new("SIGUSR1").signo

e = Marshal.load(Marshal.dump(SignalException.new("TERM")))
p e.signo, e.message, e.class
e = Marshal.load(Marshal.dump(Interrupt.new("x")))
p e.signo, e.message, e.class

[2**64, -1, 1000].each do |n|
  SignalException.new(n)
rescue => e
  p [e.class, e.message]
end
begin
  SignalException.new("TERM".encode("UTF-16LE"))
rescue => e
  p [e.class, e.message]
end
[2**70, "TERM".encode("UTF-16LE")].each do |sig|
  trap(sig) {}
rescue => e
  p [e.class, e.message]
end
begin
  Process.kill("TERM".encode("UTF-16LE"), $$)
rescue => e
  p [e.class, e.message]
end
