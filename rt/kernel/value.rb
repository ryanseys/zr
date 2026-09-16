# Values: CRuby's tagging. A fixnum is `n << 1 | 1`; false is 0, nil 8,
# true 0x14, undef 0x34; a static symbol is `id << 8 | 0x0c`; everything
# else is a pointer to a cell whose header is an RBasic. `undef` never
# reaches Ruby: it means a signal is pending.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void
Machine.import "abort", [] => Void
Machine.import "malloc", [Word] => Ptr
Machine.import "posix_memalign", [Ptr, Word, Word] => I32
Machine.import "free", [Ptr] => Void
Machine.import "memmove", [Ptr, Ptr, Word] => Ptr
Machine.import "memset", [Ptr, I32, Word] => Ptr
Machine.import "getenv", [Ptr] => Ptr

# malloc that answers a block, or ends the program as CRuby does when
# memory runs out: the kernel cannot unwind from inside an allocation,
# so no NoMemoryError can reach Ruby from here. The bytes asked for
# count toward the payload the heap collects by (rt/kernel/heap.rb),
# and zr_xfree takes the block's own size off again: what a block
# holds past the ask is not counted in, so the count runs under the
# payload held, never over it, and stops at zero.
sig [Word] => Ptr
machine def zr_xmalloc(n)
  p = malloc(n)
  if p == 0 && n != 0
    zr_memory_exhausted()
  end
  h = zr_heap()
  Heap.set_malloced(h, Heap.malloced(h) + n)
  p
end

sig [Ptr] => Void
machine def zr_xfree(p)
  if p != 0
    h = zr_heap()
    size = zr_os_malloc_size(p)
    Heap.set_malloced(h, size > Heap.malloced(h) ? 0 : Heap.malloced(h) - size)
    free(p)
  end
end

# Whether the machine can give a buffer of `n` bytes, which CRuby finds
# out by allocating the buffer a read asks for. A read asks here first,
# so a length no allocator can serve raises NoMemoryError in the program
# rather than ending the process.
sig [Value] => Value
machine def zr_memory_for_p(n)
  size = zr_fix2long(n)
  if size <= 0
    return Machine.value(QFALSE)
  end
  room = malloc(Machine.word(size))
  if Machine.word(room) == 0
    return Machine.value(QFALSE)
  end
  free(room)
  Machine.value(QTRUE)
end

# CRuby's words, and its status, when it cannot get memory.
sig [] => Void
machine def zr_memory_exhausted
  write(Machine.i32(2), Machine.bytes("[FATAL] failed to allocate memory\n"), 34)
  exit(Machine.i32(1))
end

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
# A module whose name is temporary (`set_temporary_name`): a constant
# assignment still names it.
FL_TEMP_NAME = 1 << 14
# A String's encoding, as ruby's own index into `Encoding.list`: 0
# ASCII-8BIT, 1 UTF-8, 2 US-ASCII, then one number for each of the
# other hundred. Eight bits over the flags hold it, with 0 and 1
# swapped, so a String that never named an encoding reads as UTF-8.
FL_ENC_SHIFT = 24
FL_ENC_KEEP = 0 - ((255 << 24) + 1)
ENC_BINARY = 0
ENC_UTF8 = 1
ENC_USASCII = 2
ENC_CESU8 = 15
# No encoding: what two Strings that cannot join would take.
ENC_NONE = 255
# UTF-16 and UTF-32 in each byte order, then their two dummy names:
# the encodings whose ASCII bytes are not ASCII characters.
ENC_UTF16BE = 3
ENC_UTF16LE = 4
ENC_UTF32BE = 5
ENC_UTF32LE = 6
ENC_UTF32 = 8
# A symbol row keeps the same tag in its length word, this far up.
SYM_TAG_SHIFT = 56
# A Hash that compares keys by identity (`compare_by_identity`).
FL_IDENTITY = 1 << 17
# A Hash a `ruby2_keywords` method took from keywords into its rest.
FL_RUBY2 = 1 << 18

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
  elsif zr_flonum_p(v)
    T_FLOAT
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

# libc's memmove, which is safe for the ranges that overlap: a caller
# that shifts within one buffer needs no second routine.
sig [Ptr, Ptr, Word] => Void
machine def zr_memcpy(to, from, n)
  memmove(to, from, n)
end

# A stop for a core method that reaches a case it does not answer
# yet: a NotImplementedError naming it, never a wrong answer. A program
# may rescue it, as it may rescue ruby's own on a platform that lacks
# the feature.
sig [Value] => Value
machine def zr_unimplemented(what)
  zr_raise_stop(zr_core_class(Machine.id(:NotImplementedError)), what)
end

# A call this OS does not have: the NotImplementedError rb_notimplement
# raises, `<name>() function is unimplemented on this machine`.
sig [Ptr, Word] => Value
machine def zr_notimplement(name, len)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, name, len)
  zr_buf_push(b, Machine.bytes("() function is unimplemented on this machine"), 44)
  zr_raise_buf(zr_core_class(Machine.id(:NotImplementedError)), b)
end

# A feature ruby carries that this runtime has no file for: a LoadError
# naming it, so the `rescue LoadError` a library guards an optional
# require with still runs.
sig [Value] => Value
machine def zr_unloadable(what)
  zr_raise_stop(zr_core_class(Machine.id(:LoadError)), what)
end

sig [Value, Value] => Value
machine def zr_raise_stop(klass, what)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_str(b, what)
  zr_buf_push(b, Machine.bytes(" is not implemented yet"), 23)
  zr_raise_buf(klass, b)
end
