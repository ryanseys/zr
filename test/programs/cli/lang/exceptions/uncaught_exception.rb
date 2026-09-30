# An uncaught exception prints the message and the backtrace and exits 1. The
# linked binary carries the source names its backtrace needs.
def inner
  raise ArgumentError, "bad thing"
end

def outer
  inner
end

outer



