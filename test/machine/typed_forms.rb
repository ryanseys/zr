# The typed forms of the kernel: a layout as `class Name < Layout`, read
# through a view (`RString[s].len`), a view in a local and as a typed
# parameter, an import as a typed def of `module Libc`, and a signature
# as a module with a typed `call`. It writes what structs.rb writes, and
# then calls through a pointer.
module Zr::Kern
  module Libc
    #: (i32, ptr, word) -> word
    def self.write(fd, buf, count) = Machine.import
    #: (i32) -> void
    def self.exit(status) = Machine.import
  end

  module Binop
    #: (ptr, word, word) -> word
    def self.call(fn, a, b) = Machine.indirect
  end

  class RBasic < Layout
    attr_accessor :flags #: word
    attr_accessor :klass #: value
  end

  class RString < Layout
    attr_reader :basic #: RBasic
    attr_accessor :len #: word
    attr_accessor :capa #: word
    attr_accessor :ptr #: ptr
    attr_accessor :enc #: i32
    attr_accessor :cr #: i8
    attr_accessor :frozen #: bool
  end

  STRING_BYTES = RString.size
  ARENA = STRING_BYTES * 4

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

  #: () -> ptr
  def arena
    Machine.static(:arena, ARENA)
  end

  # A view as a parameter: the header of a String.
  #: (RBasic, word, word) -> void
  def set_header(basic, flags, klass)
    basic.flags = flags
    basic.klass = Machine.value(klass)
  end

  #: (word, word) -> word
  def add(a, b)
    a + b
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    put_word(RBasic.size)
    put_word(RString.size)
    put_word(ARENA)
    s = arena() + STRING_BYTES
    set_header(RString[s].basic, 5, 77)
    str = RString[s]
    str.len = 3
    str.capa = 16
    str.ptr = Machine.bytes("abc")
    str.enc = 2
    str.cr = 1
    str.frozen = true
    put_word(RBasic[s].flags)
    put_word(Machine.word(RString[s].basic.klass))
    put_word(str.len)
    put_word(str.capa)
    Libc.write(1, str.ptr, str.len)
    Libc.write(1, Machine.bytes("\n"), 1)
    put_word(Machine.u32(str.enc))
    put_word(Machine.u8(str.cr))
    put_word(Machine.word(str.frozen))
    # the neighbours are untouched
    put_word(RString[arena()].len)
    put_word(RString[s + STRING_BYTES].len)
    put_word(Binop.call(Machine.addr(:add), 40, 2))
    Libc.exit(0)
    0
  end
end
