# One file of a three-file unit: the imports, a constant, and a printer
# the other files call.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void

BASE = 10

sig [Word] => Void
machine def put_word(n)
  buf = Machine.slot(24)
  at = 23
  Machine.store8(buf + at, 0, Machine.i8(10))
  if n == 0
    at = at - 1
    Machine.store8(buf + at, 0, Machine.i8(48))
  end
  while n > 0
    at = at - 1
    Machine.store8(buf + at, 0, Machine.i8(48 + (n % BASE)))
    n = n / BASE
  end
  write(1, buf + at, 24 - at)
end
