# Struct layouts: natural alignment, an embedded struct, readers and
# writers of every width, and a constant folded from a struct's size.
# The program prints the fields it wrote back through the readers.
module Zr::Kern
  module Libc
    #: (i32, ptr, word) -> word
    def self.write(i, p, n) = Machine.import
    #: (i32) -> void
    def self.exit(i) = Machine.import
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

  #: (i32, ptr) -> i32
  def main(argc, argv)
    put_word(RBasic.size)
    put_word(RString.size)
    put_word(ARENA)
    s = arena() + STRING_BYTES
    RBasic[RString[s].basic].flags = 5
    RBasic[RString[s].basic].klass = Machine.value(77)
    RString[s].len = 3
    RString[s].capa = 16
    RString[s].ptr = Machine.bytes("abc")
    RString[s].enc = 2
    RString[s].cr = 1
    RString[s].frozen = true
    put_word(RBasic[s].flags)
    put_word(Machine.word(RBasic[RString[s].basic].klass))
    put_word(RString[s].len)
    put_word(RString[s].capa)
    Libc.write(1, RString[s].ptr, RString[s].len)
    Libc.write(1, Machine.bytes("\n"), 1)
    put_word(Machine.u32(RString[s].enc))
    put_word(Machine.u8(RString[s].cr))
    put_word(Machine.word(RString[s].frozen))
    # the neighbours are untouched
    put_word(RString[arena()].len)
    put_word(RString[s + STRING_BYTES].len)
    Libc.exit(0)
    0
  end
end
