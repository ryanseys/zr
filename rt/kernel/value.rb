# Values: CRuby's tagging. A fixnum is `n << 1 | 1`; false is 0, nil 8,
# true 0x14, undef 0x34; a static symbol is `id << 8 | 0x0c`; everything
# else is a pointer to a cell whose header is an RBasic. `undef` never
# reaches Ruby: it means a signal is pending.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void
Machine.import "abort", [] => Void
Machine.import "malloc", [Word] => Ptr
Machine.import "free", [Ptr] => Void
Machine.import "getenv", [Ptr] => Ptr
Machine.import "pthread_self", [] => Ptr
Machine.import "pthread_get_stackaddr_np", [Ptr] => Ptr
Machine.import "pthread_get_stacksize_np", [Ptr] => Word

QFALSE = 0
QNIL = 8
QTRUE = 20
QUNDEF = 52
SYMBOL_TAG = 12

# Type tags, CRuby's numbering, in the low five bits of the flags.
T_NONE = 0
T_OBJECT = 1
T_CLASS = 2
T_MODULE = 3
T_STRING = 5
T_ARRAY = 7
T_NIL = 17
T_TRUE = 18
T_FALSE = 19
T_SYMBOL = 20
T_FIXNUM = 21
T_MASK = 31
# Flag bits above the type.
FL_ALLOCATED = 1 << 5
FL_MARK = 1 << 6
FL_FREEZE = 1 << 11
# An object whose kind has no ivar table of its own keeps one beside
# the arena, indexed by its cell.
FL_EXIVAR = 1 << 10
# A singleton class: one object's own, `attached`, ahead of its class.
FL_SINGLETON = 1 << 12
# A String of bytes (CRuby's ASCII-8BIT): each byte is a character,
# and `inspect` spells the high ones in hex.
FL_BINARY = 1 << 13

Machine.struct :RBasic, flags: Word, klass: Value

sig [Value] => Bool
machine def zr_fixnum_p(v)
  (Machine.word(v) & 1) == 1
end

# Not a pointer to a cell.
sig [Value] => Bool
machine def zr_special_p(v)
  w = Machine.word(v)
  (w & 7) != 0 || w == 0 || w == 8
end

sig [Word] => Value
machine def zr_fix(n)
  Machine.value((n << 1) | 1)
end

sig [Value] => Word
machine def zr_fix2long(v)
  Machine.word(v) >> 1
end

sig [Word] => Value
machine def zr_sym(id)
  Machine.value((id << 8) | SYMBOL_TAG)
end

sig [Value] => Word
machine def zr_sym2id(v)
  Machine.word(v) >> 8
end

sig [Value] => Bool
machine def zr_symbol_p(v)
  (Machine.word(v) & 255) == SYMBOL_TAG
end

sig [Value] => Word
machine def zr_type(v)
  if zr_fixnum_p(v)
    T_FIXNUM
  elsif v == QNIL
    T_NIL
  elsif v == QTRUE
    T_TRUE
  elsif v == QFALSE
    T_FALSE
  elsif zr_symbol_p(v)
    T_SYMBOL
  else
    RBasic.flags(v) & T_MASK
  end
end

sig [Ptr, Word] => Void
machine def zr_write_out(bytes, len)
  write(1, bytes, len)
end

sig [Ptr, Word] => Void
machine def zr_write_err(bytes, len)
  write(2, bytes, len)
end

# A message on stderr, then abort: a bug in the runtime, never a Ruby error.
sig [Ptr, Word] => Void
machine def zr_bug(bytes, len)
  write(2, bytes, len)
  abort()
end

sig [Ptr, Ptr, Word] => Void
machine def zr_memcpy(to, from, n)
  i = 0
  while i < n
    Machine.store8(to + i, 0, Machine.load8(from + i, 0))
    i += 1
  end
end

# A stop for a core method that reaches a case it does not answer
# yet: the program aborts naming it, never with a wrong answer.
sig [Value] => Value
machine def zr_unimplemented(what)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("ze0: "), 5)
  zr_buf_str(b, what)
  zr_buf_push(b, Machine.bytes(" is not implemented yet\n"), 24)
  zr_bug(Buf.ptr(b), Buf.len(b))
  Machine.value(QNIL)
end
