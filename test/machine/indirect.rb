# Calls through function pointers: a table of operators in a static area,
# each taken with Machine.addr and called through one Machine.sig, and a
# visitor that walks the table through a pointer it was handed.
module Zr::Kern
  Libc.import :write, [I32, Ptr, Word] => Word
  Libc.import :exit, [I32] => Void

  Binop = fn [Word, Word] => Word
  Each = fn [Ptr, Word] => Void

  sig [Word, Word] => Word
  def add(a, b)
    a + b
  end

  sig [Word, Word] => Word
  def mul(a, b)
    a * b
  end

  sig [Word, Word] => Word
  def sub(a, b)
    a - b
  end

  sig [Word] => Void
  def put_word(n)
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
    Libc.write(1, buf + at, 24 - at)
  end

  # table: three binop pointers
  sig [] => Ptr
  def table
    t = Machine.static(:table, 24)
    Machine.store64(t, 0, Machine.word(Machine.addr(:add)))
    Machine.store64(t, 8, Machine.word(Machine.addr(:mul)))
    Machine.store64(t, 16, Machine.word(Machine.addr(:sub)))
    t
  end

  sig [Ptr, Word] => Void
  def show(fn, n)
    put_word(Binop.call(fn, 20, n))
  end

  sig [Ptr, Ptr, Word] => Void
  def walk(t, visit, n)
    i = 0
    while i < 3
      Each.call(visit, Machine.ptr(Machine.load64(t, 0)), n)
      t = t + 8
      i += 1
    end
  end

  sig [I32, Ptr] => I32
  def main(argc, argv)
    t = table()
    walk(t, Machine.addr(:show), 4)
    # a pointer read back from memory and compared
    fn = Machine.ptr(Machine.load64(t, 8))
    put_word(Binop.call(fn, 6, 7))
    if fn == Machine.addr(:mul)
      put_word(1)
    end
    Libc.exit(0)
    0
  end
end
