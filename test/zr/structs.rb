# Struct layouts: natural alignment, an embedded struct, readers and
# writers of every width, and a constant folded from a struct's size.
# The program prints the fields it wrote back through the readers.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void

Machine.struct :RBasic, flags: Word, klass: Value
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr, enc: I32, cr: I8, frozen: Bool
STRING_BYTES = RString.size
ARENA = STRING_BYTES * 4

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

sig [] => Ptr
machine def arena
  Machine.static(:arena, ARENA)
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  put_word(RBasic.size)
  put_word(RString.size)
  put_word(ARENA)
  s = arena() + STRING_BYTES
  RBasic.set_flags(RString.basic(s), 5)
  RBasic.set_klass(RString.basic(s), Machine.value(77))
  RString.set_len(s, 3)
  RString.set_capa(s, 16)
  RString.set_ptr(s, Machine.bytes("abc"))
  RString.set_enc(s, 2)
  RString.set_cr(s, 1)
  RString.set_frozen(s, true)
  put_word(RBasic.flags(s))
  put_word(Machine.word(RBasic.klass(RString.basic(s))))
  put_word(RString.len(s))
  put_word(RString.capa(s))
  write(1, RString.ptr(s), RString.len(s))
  write(1, Machine.bytes("\n"), 1)
  put_word(Machine.word(RString.enc(s)))
  put_word(Machine.word(RString.cr(s)))
  put_word(Machine.word(RString.frozen(s)))
  # the neighbours are untouched
  put_word(RString.len(arena()))
  put_word(RString.len(s + STRING_BYTES))
  exit(0)
  0
end
