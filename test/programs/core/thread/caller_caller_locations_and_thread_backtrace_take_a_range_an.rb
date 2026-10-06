# caller, caller_locations and Thread#backtrace take a Range over the
# frames from their level 0, and the current thread's backtrace starts
# at its own frame, as ruby's does.
def a = b
def b = c
def c
  p caller(0..0), caller(1..1), caller(..0).size, caller(2..), caller(50..)
  p caller_locations(0..0).map(&:label), caller_locations(1..).map(&:label)
  p Thread.current.backtrace(0..0), Thread.current.backtrace_locations(0..1).map(&:label)
  p Thread.current.backtrace(1, 1)
end
a
