# Calls through function pointers: a table of operators in a static area,
# each taken with Machine.addr and called through one Machine.sig, and a
# visitor that walks the table through a pointer it was handed.
module Zr::Kern
  module Libc
    #: (i32, ptr, word) -> word
    def self.write(i, p, n) = Machine.import
    #: (i32) -> void
    def self.exit(i) = Machine.import
  end

  module Binop
    #: (ptr, word, word) -> word
    def self.call(fn, n1, n2) = Machine.indirect
  end

  module Each
    #: (ptr, ptr, word) -> void
    def self.call(fn, p, n) = Machine.indirect
  end

  #: (word, word) -> word
  def add(a, b)
    a + b
  end

  #: (word, word) -> word
  def mul(a, b)
    a * b
  end

  #: (word, word) -> word
  def sub(a, b)
    a - b
  end

  #: (word) -> void
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
  #: () -> ptr
  def table
    t = Machine.static(:table, 24)
    Machine.store64(t, 0, Machine.word(Machine.addr(:add)))
    Machine.store64(t, 8, Machine.word(Machine.addr(:mul)))
    Machine.store64(t, 16, Machine.word(Machine.addr(:sub)))
    t
  end

  #: (ptr, word) -> void
  def show(fn, n)
    put_word(Binop.call(fn, 20, n))
  end

  #: (ptr, ptr, word) -> void
  def walk(t, visit, n)
    i = 0
    while i < 3
      Each.call(visit, Machine.ptr(Machine.load64(t, 0)), n)
      t = t + 8
      i += 1
    end
  end

  #: (i32, ptr) -> i32
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
