module Zr::Kern
  # Values use CRuby's tagging. A fixnum is `n << 1 | 1`. false is 0, nil
  # is 8, true is 0x14 and undef is 0x34. A static symbol is
  # `id << 8 | 0x0c`. All other values are pointers to a cell whose header
  # is an RBasic. `undef` never gets to Ruby: it means a pending unwind.
  Libc.import :write, [I32, Ptr, Word] => Word
  Libc.import :exit, [I32] => Void
  Libc.import :abort, [] => Void
  Libc.import :malloc, [Word] => Ptr
  Libc.import :posix_memalign, [Ptr, Word, Word] => I32
  Libc.import :free, [Ptr] => Void
  Libc.import :memmove, [Ptr, Ptr, Word] => Ptr
  Libc.import :memset, [Ptr, I32, Word] => Ptr
  Libc.import :getenv, [Ptr] => Ptr

  # malloc that returns a block, or ends the program as CRuby does when no
  # memory is available. The kernel cannot unwind from inside an
  # allocation, so no NoMemoryError can get to Ruby from here. The
  # requested bytes count toward the malloc total that starts a collection
  # (lib/zr/runtime/kernel/heap.rb). zr_xfree subtracts the block's real size,
  # which can be larger than the request. Thus the total can be less than
  # the real total, but never more, and it stops at zero.
  sig [Word] => Ptr
  def zr_xmalloc(n)
    p = Libc.malloc(n)
    if p == 0 && n != 0
      zr_memory_exhausted()
    end
    h = zr_heap()
    Heap.set_malloced(h, Heap.malloced(h) + n)
    if Heap.malloced(h) > Heap.malloc_limit(h)
      Heap.set_slow(h, 1)
    end
    p
  end

  sig [Ptr] => Void
  def zr_xfree(p)
    if p != 0
      zr_sized_xfree(p, zr_os_malloc_size(p))
    end
  end

  # A free for a caller that knows the block's size.
  #
  # `zr_xfree` gets the size from the allocator (`zr_os_malloc_size`:
  # `malloc_size` on darwin, `malloc_usable_size` on linux). A sweep does
  # not need that call, because each buffer of a cell records its size: a
  # String's capacity plus a NUL, an Array's capacity in words plus the
  # front gap from a shift, the entry count of an ivar table or a Hash.
  #
  # The malloc total is also more accurate. `zr_xmalloc` adds the
  # requested bytes, but `zr_xfree` subtracts the allocated bytes, which
  # can be more. Thus `Heap.malloced` gets smaller each time a buffer is
  # used again, and the malloc trigger starts a collection too late. The
  # `size > malloced` clamp hides this at zero. A caller that gives the
  # requested size subtracts exactly what was added.
  sig [Ptr, Word] => Void
  def zr_sized_xfree(p, n)
    if p != 0
      h = zr_heap()
      Heap.set_malloced(h, n > Heap.malloced(h) ? 0 : Heap.malloced(h) - n)
      Libc.free(p)
    end
  end

  # Whether the machine can allocate a buffer of `n` bytes. CRuby finds
  # this out when it allocates the buffer for a read. A read calls this
  # first, so that a length too large for the allocator raises
  # NoMemoryError in the program and does not end the process.
  sig [Value] => Value
  def zr_memory_for_p(n)
    size = zr_fix2long(n)
    if size <= 0
      return Machine.value(QFALSE)
    end
    room = Libc.malloc(Machine.word(size))
    if Machine.word(room) == 0
      return Machine.value(QFALSE)
    end
    Libc.free(room)
    Machine.value(QTRUE)
  end

  # Writes CRuby's message and exits with CRuby's status when no memory is
  # available.
  sig [] => Void
  def zr_memory_exhausted
    Libc.write(Machine.i32(2), Machine.bytes("[FATAL] failed to allocate memory\n"), 34)
    Libc.exit(Machine.i32(1))
  end

  QFALSE = 0
  QNIL = 8
  QTRUE = 20
  QUNDEF = 52
  SYMBOL_TAG = 12

  # Type tags, with CRuby's numbers, in the low five bits of the flags.
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
  FL_FREEZE = 1 << 11
  # An object of a kind with no ivar table field keeps its ivar table in a
  # side table next to the arena, indexed by its cell.
  FL_EXIVAR = 1 << 10
  # A singleton class: it belongs to one object (`attached`), and it is
  # before that object's class in the ancestor list.
  FL_SINGLETON = 1 << 12
  # A module with a temporary name (`set_temporary_name`). A constant
  # assignment can still give it a permanent name.
  FL_TEMP_NAME = 1 << 14
  # A String's encoding, as ruby's index into `Encoding.list`: 0 is
  # ASCII-8BIT, 1 is UTF-8, 2 is US-ASCII, then one number for each of the
  # other hundred. It is in eight bits of the flags, with 0 and 1 swapped,
  # so a String with no encoding set reads as UTF-8.
  FL_ENC_SHIFT = 24
  FL_ENC_KEEP = 0 - ((255 << 24) + 1)
  ENC_BINARY = 0
  ENC_UTF8 = 1
  ENC_USASCII = 2
  ENC_CESU8 = 15
  # No encoding: the result for two Strings that are not compatible.
  ENC_NONE = 255
  # UTF-16 and UTF-32 in each byte order, then their two dummy names.
  # These are the encodings in which ASCII bytes are not ASCII characters.
  ENC_UTF16BE = 3
  ENC_UTF16LE = 4
  ENC_UTF32BE = 5
  ENC_UTF32LE = 6
  ENC_UTF32 = 8
  # A symbol entry keeps the same tag in its length word, at this shift.
  SYM_TAG_SHIFT = 56
  # A Hash that compares keys by identity (`compare_by_identity`).
  FL_IDENTITY = 1 << 17
  # A Hash that a `ruby2_keywords` method made from keywords for its rest
  # parameter.
  FL_RUBY2 = 1 << 18
  # A class under Object with a rank table (zr_class_rank), which is not
  # boxed and is not a box's shadow. At the site, the type checks
  # (`is_a?`, `===`, `nil?`) use only its table and its flags, and do not
  # walk the ancestor list.
  FL_RANKED = 1 << 34
  FL_RANKED_CLEAR = 0 - FL_RANKED - 1
  # A class or module that eval support made while the program ran. ruby's
  # compiler is C and makes none, so ObjectSpace and `subclasses` show
  # neither it nor its instances.
  FL_CONCEALED = 1 << 36

  RBasic = layout flags: Word, klass: Value

  sig [Value] => Bool
  def zr_fixnum_p(v)
    (Machine.word(v) & 1) == 1
  end

  # Whether `v` is not a pointer to a cell.
  sig [Value] => Bool
  def zr_special_p(v)
    w = Machine.word(v)
    (w & 7) != 0 || w == 0 || w == 8
  end

  sig [Word] => Value
  def zr_fix(n)
    Machine.value((n << 1) | 1)
  end

  sig [Value] => Word
  def zr_fix2long(v)
    Machine.word(v) >> 1
  end

  sig [Word] => Value
  def zr_sym(id)
    Machine.value((id << 8) | SYMBOL_TAG)
  end

  sig [Value] => Word
  def zr_sym2id(v)
    Machine.word(v) >> 8
  end

  sig [Value] => Bool
  def zr_symbol_p(v)
    (Machine.word(v) & 255) == SYMBOL_TAG
  end

  # Whether `v` is a class or a module: a cell of either type.
  sig [Value] => Bool
  def zr_module_p(v)
    if zr_special_p(v)
      return false
    end
    t = RBasic.flags(v) & T_MASK
    t == T_CLASS || t == T_MODULE
  end

  sig [Value] => Word
  def zr_type(v)
    # Check for a heap object first. Its type is in its header
    # (zr_class_of).
    if (Machine.word(v) & 7) == 0 && Machine.word(v) > QUNDEF
      return RBasic.flags(v) & T_MASK
    end
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
  def zr_write_out(bytes, len)
    Libc.write(1, bytes, len)
  end

  sig [Ptr, Word] => Void
  def zr_write_err(bytes, len)
    Libc.write(2, bytes, len)
  end

  # Writes a message to stderr, then aborts. It is for a bug in the
  # runtime, never for a Ruby error.
  sig [Ptr, Word] => Void
  def zr_bug(bytes, len)
    Libc.write(2, bytes, len)
    Libc.abort()
  end

  # libc's memmove, which is safe for ranges that overlap. Thus a caller
  # that shifts bytes within one buffer needs no other routine.
  sig [Ptr, Ptr, Word] => Void
  def zr_memcpy(to, from, n)
    Libc.memmove(to, from, n)
  end

  # Stops a core method that gets a case it does not support. It raises a
  # NotImplementedError that gives the case, and never returns a wrong
  # result. A program can rescue it, as it can rescue ruby's error on a
  # platform that does not have the feature.
  sig [Value] => Value
  def zr_unimplemented(what)
    zr_raise_stop(zr_core_class(Machine.id(:NotImplementedError)), what)
  end

  # For a call that this OS does not have. Raises the NotImplementedError
  # that rb_notimplement raises: `<name>() function is unimplemented on
  # this machine`.
  sig [Ptr, Word] => Value
  def zr_notimplement(name, len)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, name, len)
    zr_buf_push(b, Machine.bytes("() function is unimplemented on this machine"), 44)
    zr_raise_buf(zr_core_class(Machine.id(:NotImplementedError)), b)
  end

  # For a ruby feature that this runtime has no file for. Raises a
  # LoadError that gives the feature, so that a library's
  # `rescue LoadError` around an optional require still runs.
  sig [Value] => Value
  def zr_unloadable(what)
    zr_raise_stop(zr_core_class(Machine.id(:LoadError)), what)
  end

  sig [Value, Value] => Value
  def zr_raise_stop(klass, what)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_str(b, what)
    zr_buf_push(b, Machine.bytes(" is not implemented yet"), 23)
    zr_raise_buf(klass, b)
  end
end
