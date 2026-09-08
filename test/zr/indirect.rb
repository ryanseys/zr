# Calls through function pointers: a table of operators in a static area,
# each taken with Machine.addr and called through one Machine.sig, and a
# visitor that walks the table through a pointer it was handed.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void

Machine.sig :binop, [Word, Word] => Word
Machine.sig :each, [Ptr, Word] => Void

sig [Word, Word] => Word
machine def add(a, b)
  a + b
end

sig [Word, Word] => Word
machine def mul(a, b)
  a * b
end

sig [Word, Word] => Word
machine def sub(a, b)
  a - b
end

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
    Machine.store8(buf + at, 0, Machine.i8(48 + (n % 10)))
    n = n / 10
  end
  write(1, buf + at, 24 - at)
end

# table: three binop pointers
sig [] => Ptr
machine def table
  t = Machine.static(:table, 24)
  Machine.store64(t, 0, Machine.word(Machine.addr(:add)))
  Machine.store64(t, 8, Machine.word(Machine.addr(:mul)))
  Machine.store64(t, 16, Machine.word(Machine.addr(:sub)))
  t
end

sig [Ptr, Word] => Void
machine def show(fn, n)
  put_word(Machine.call(:binop, fn, 20, n))
end

sig [Ptr, Ptr, Word] => Void
machine def walk(t, visit, n)
  i = 0
  while i < 3
    Machine.call(:each, visit, Machine.ptr(Machine.load64(t, 0)), n)
    t = t + 8
    i += 1
  end
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  t = table()
  walk(t, Machine.addr(:show), 4)
  # a pointer read back from memory and compared
  fn = Machine.ptr(Machine.load64(t, 8))
  put_word(Machine.call(:binop, fn, 6, 7))
  if fn == Machine.addr(:mul)
    put_word(1)
  end
  exit(0)
  0
end
