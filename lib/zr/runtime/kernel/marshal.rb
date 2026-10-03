module Zr::Kern
  # A fast Marshal reader for the kinds that most dumps contain: nil, the
  # booleans, fixnums, floats, symbols and symbol links, strings with
  # their encoding, arrays, hashes, plain objects and structs, a `_load`
  # payload (usually an Encoding), a bignum that fits a fixnum, and links
  # to any of these. For all other kinds (`marshal_load`, a class or
  # module, a regexp, a larger bignum, an extended or subclassed value, a
  # hash with a default, an object of a class with its own allocator), the
  # read falls back to the Ruby reader (lib/zr/runtime/core/marshal.rb). The Ruby
  # reader then reads the document from the start. Both readers give the
  # same values. This one reads at about the speed of a copy, which is
  # necessary for a cache of parses or of compiled units.
  #
  # The reader state is on the stack: the bytes, the length, the position,
  # and a bail flag. The object table and the symbol table are in two
  # Arrays that the caller keeps, because a stack slot is not a GC root.
  class MReader < Layout
    attr_accessor :bytes #: ptr
    attr_accessor :len #: word
    attr_accessor :pos #: word
    attr_accessor :bail #: word
  end

  MR_NIL = 0x30
  MR_TRUE = 0x54
  MR_FALSE = 0x46
  MR_FIXNUM = 0x69
  MR_SYMBOL = 0x3a
  MR_SYMLINK = 0x3b
  MR_LINK = 0x40
  MR_IVARS = 0x49
  MR_FLOAT = 0x66
  MR_STRING = 0x22
  MR_ARRAY = 0x5b
  MR_HASH = 0x7b
  MR_OBJECT = 0x6f
  MR_STRUCT = 0x53
  MR_USRDEF = 0x75
  MR_BIGNUM = 0x6c

  # `Marshal.load(bytes)` for a String. It returns nil when the Ruby
  # reader must read the document: another format version, a truncated
  # document, or a kind that this reader leaves to Ruby. Then
  # zr_marshal_bailed_p returns true. Undef means a raise, which the caller
  # passes on.
  #: (value) -> value
  def zr_marshal_load_fast(src)
    Machine.store64(Machine.static(:marshal_bailed, 8), 0, 0)
    r = Machine.slot(MReader.size)
    MReader[r].bytes = RString[src].ptr
    MReader[r].len = RString[src].len
    MReader[r].pos = 2
    MReader[r].bail = 0
    if RString[src].len < 2 || Machine.u8(Machine.load8(RString[src].ptr, 0)) != 4 || Machine.u8(Machine.load8(RString[src].ptr, 1)) > 8
      zr_mr_bail(r)
      return Machine.value(QNIL)
    end
    objects = zr_ary_new(64)
    symbols = zr_ary_new(64)
    v = zr_mr_value(r, objects, symbols)
    if MReader[r].bail != 0
      return Machine.value(QNIL)
    end
    if v == QUNDEF
      return v
    end
    # The Ruby reader also handles bytes after the value, so that the
    # result is the same as ruby's.
    if MReader[r].pos != MReader[r].len
      zr_mr_bail(r)
      return Machine.value(QNIL)
    end
    v
  end

  # Whether the fast reader stopped and left the document to the Ruby
  # reader (and did not read it or raise).
  #: () -> value
  def zr_marshal_bailed_p
    Machine.value(Machine.load64(Machine.static(:marshal_bailed, 8), 0) != 0 ? QTRUE : QFALSE)
  end

  # Stops the fast reader. Returns undef and sets the bail flag for the
  # caller.
  #: (ptr) -> value
  def zr_mr_bail(r)
    MReader[r].bail = 1
    Machine.store64(Machine.static(:marshal_bailed, 8), 0, 1)
    Machine.value(QUNDEF)
  end

  # Returns the next byte, or -1 at the end. The end means a truncated
  # document, so the reader bails and the Ruby reader raises the error.
  #: (ptr) -> word
  def zr_mr_byte(r)
    pos = MReader[r].pos
    if pos >= MReader[r].len
      zr_mr_bail(r)
      return 0 - 1
    end
    MReader[r].pos = pos + 1
    Machine.u8(Machine.load8(MReader[r].bytes + pos, 0))
  end

  # Reads a packed integer: one byte for a small number, or a count byte
  # and then that number of bytes, least significant first. Returns -1 for
  # a truncated number. No packed count or index is negative.
  #: (ptr) -> word
  def zr_mr_long(r)
    head = zr_mr_byte(r)
    if head < 0
      return 0 - 1
    end
    if head > 127
      head -= 256
    end
    if head == 0
      return 0
    end
    if head > 4
      return head - 5
    end
    if head < 0 - 4
      return head + 5
    end
    count = head > 0 ? head : 0 - head
    value = head > 0 ? 0 : 0 - 1
    i = 0
    while i < count
      b = zr_mr_byte(r)
      if b < 0
        return 0 - 1
      end
      value = (value & (0 - 1 - (255 << (8 * i)))) | (b << (8 * i))
      i += 1
    end
    value
  end

  # Returns a pointer to the next `n` bytes and moves past them. Returns 0
  # if fewer than `n` bytes remain.
  #: (ptr, word) -> ptr
  def zr_mr_text(r, n)
    pos = MReader[r].pos
    if n < 0 || pos + n > MReader[r].len
      return 0
    end
    MReader[r].pos = pos + n
    MReader[r].bytes + pos
  end

  # Whether the `n` bytes at `p` are all ASCII. A symbol with a non-ASCII
  # byte needs its own encoding for intern, and the Ruby reader finds it.
  #: (ptr, word) -> bool
  def zr_mr_ascii_p(p, n)
    i = 0
    while i < n
      if Machine.u8(Machine.load8(p + i, 0)) > 127
        return false
      end
      i += 1
    end
    true
  end

  # Reads a symbol, new or linked, and returns its id. Returns -1 for any
  # other kind.
  #: (ptr, value) -> word
  def zr_mr_symbol(r, symbols)
    tag = zr_mr_byte(r)
    if tag == MR_SYMLINK
      i = zr_mr_long(r)
      if i < 0 || i >= RArray[symbols].len
        return 0 - 1
      end
      return zr_sym2id(zr_ary_at(symbols, i))
    end
    if tag != MR_SYMBOL
      return 0 - 1
    end
    n = zr_mr_long(r)
    p = zr_mr_text(r, n)
    if p == 0 || !zr_mr_ascii_p(p, n)
      return 0 - 1
    end
    id = zr_intern(p, n)
    zr_ary_push(symbols, zr_sym(id))
    id
  end

  # Returns the class that `path` refers to ("Prism::CallNode"). It looks
  # up one component at a time from Object. Returns undef if the path
  # refers to nothing, or to something that is not a class.
  #: (ptr, word) -> value
  def zr_mr_class(p, n)
    scope = zr_global(G_OBJECT)
    at = 0
    while at < n
      stop = at
      while stop < n && Machine.u8(Machine.load8(p + stop, 0)) != 58
        stop += 1
      end
      if stop == at
        return Machine.value(QUNDEF)
      end
      found = zr_const_lookup_at(scope, zr_intern(p + at, stop - at))
      if found == QUNDEF || zr_special_p(found) || (zr_type(found) != T_CLASS && zr_type(found) != T_MODULE)
        return Machine.value(QUNDEF)
      end
      scope = found
      at = stop
      if at < n
        if at + 2 > n || Machine.u8(Machine.load8(p + at + 1, 0)) != 58
          return Machine.value(QUNDEF)
        end
        at += 2
      end
    end
    if zr_special_p(scope) || zr_type(scope) != T_CLASS
      return Machine.value(QUNDEF)
    end
    scope
  end

  # Reads one value. Undef means a bail or a raise (`MReader.bail` tells
  # which). A value that has a link slot registers it before its parts, as
  # marshal.c does.
  #: (ptr, value, value) -> value
  def zr_mr_value(r, objects, symbols)
    tag = zr_mr_byte(r)
    if tag == MR_OBJECT
      return zr_mr_object(r, objects, symbols)
    elsif tag == MR_SYMLINK
      i = zr_mr_long(r)
      if i < 0 || i >= RArray[symbols].len
        return zr_mr_bail(r)
      end
      return zr_ary_at(symbols, i)
    elsif tag == MR_FIXNUM
      return zr_fix(zr_mr_long(r))
    elsif tag == MR_NIL
      return Machine.value(QNIL)
    elsif tag == MR_IVARS
      return zr_mr_ivars(r, objects, symbols)
    elsif tag == MR_STRING
      s = zr_mr_string(r)
      if s == QUNDEF
        return zr_mr_bail(r)
      end
      zr_ary_push(objects, s)
      return s
    elsif tag == MR_ARRAY
      return zr_mr_array(r, objects, symbols)
    elsif tag == MR_TRUE
      return Machine.value(QTRUE)
    elsif tag == MR_FALSE
      return Machine.value(QFALSE)
    elsif tag == MR_LINK
      i = zr_mr_long(r)
      if i < 0 || i >= RArray[objects].len
        return zr_mr_bail(r)
      end
      return zr_ary_at(objects, i)
    elsif tag == MR_SYMBOL
      n = zr_mr_long(r)
      p = zr_mr_text(r, n)
      if p == 0 || !zr_mr_ascii_p(p, n)
        return zr_mr_bail(r)
      end
      sym = zr_sym(zr_intern(p, n))
      zr_ary_push(symbols, sym)
      return sym
    elsif tag == MR_HASH
      return zr_mr_hash(r, objects, symbols)
    elsif tag == MR_STRUCT
      return zr_mr_struct(r, objects, symbols)
    elsif tag == MR_FLOAT
      return zr_mr_float(r, objects)
    elsif tag == MR_USRDEF
      return zr_mr_user_dump(r, objects, symbols)
    elsif tag == MR_BIGNUM
      return zr_mr_bignum(r, objects)
    end
    zr_mr_bail(r)
  end

  # `l`: a sign, a count of 16-bit words, and the words, least
  # significant first. ruby writes every integer larger than 32 bits in
  # this form (a prism location, for example), so most of them fit a
  # fixnum. A value larger than a fixnum needs the core's Bignum, which is
  # in Ruby, so the reader bails.
  #: (ptr, value) -> value
  def zr_mr_bignum(r, objects)
    sign = zr_mr_byte(r)
    words = zr_mr_long(r)
    if (sign != 43 && sign != 45) || words < 0 || words > 4
      return zr_mr_bail(r)
    end
    p = zr_mr_text(r, words * 2)
    if p == 0
      return zr_mr_bail(r)
    end
    value = 0
    i = words * 2
    while i > 0
      i -= 1
      value = (value << 8) | Machine.u8(Machine.load8(p + i, 0))
    end
    if value < 0 || value > 4611686018427387903
      return zr_mr_bail(r)
    end
    v = zr_fix(sign == 45 ? 0 - value : value)
    zr_ary_push(objects, v)
    v
  end

  # `u`: a class's `_load` on the bytes that it dumped. For an Encoding,
  # the payload is its name, and the reader finds the encoding by name, as
  # the Ruby reader does. A payload with its own ivars goes to the Ruby
  # reader.
  #: (ptr, value, value) -> value
  def zr_mr_user_dump(r, objects, symbols)
    klass = zr_mr_named_class(r, symbols)
    if klass == QUNDEF
      return zr_mr_bail(r)
    end
    payload = zr_mr_string(r)
    if payload == QUNDEF
      return zr_mr_bail(r)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(payload))
    encoding = zr_core_class(Machine.id(:Encoding))
    v = klass == encoding ? zr_send(klass, Machine.id(:find), 1, slot) : zr_send(klass, Machine.id(:_load), 1, slot)
    if v == QUNDEF
      return v
    end
    zr_ary_push(objects, v)
    v
  end

  # Reads the bytes of a string. The string is binary until an ivar gives
  # its encoding.
  #: (ptr) -> value
  def zr_mr_string(r)
    n = zr_mr_long(r)
    p = zr_mr_text(r, n)
    if p == 0
      return Machine.value(QUNDEF)
    end
    s = zr_str_new(p, n)
    zr_str_set_index(s, ENC_BINARY)
    s
  end

  # Reads a float's text with strtod, in the form that ruby's writer
  # writes: a decimal, or "inf", "-inf" or "nan".
  #: (ptr, value) -> value
  def zr_mr_float(r, objects)
    n = zr_mr_long(r)
    p = zr_mr_text(r, n)
    if p == 0
      return zr_mr_bail(r)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, p, n)
    v = zr_float_new(zr_buf_strtod(b))
    zr_ary_push(objects, v)
    v
  end

  #: (ptr, value, value) -> value
  def zr_mr_array(r, objects, symbols)
    n = zr_mr_long(r)
    if n < 0 || n > MReader[r].len
      return zr_mr_bail(r)
    end
    a = zr_ary_new(n)
    zr_ary_push(objects, a)
    i = 0
    while i < n
      v = zr_mr_value(r, objects, symbols)
      if v == QUNDEF
        return v
      end
      zr_ary_push(a, v)
      i += 1
    end
    a
  end

  # Reads a hash with no default. A key that runs Ruby code for its hash
  # (an object with its own `hash`) goes to the Ruby reader.
  #: (ptr, value, value) -> value
  def zr_mr_hash(r, objects, symbols)
    n = zr_mr_long(r)
    if n < 0 || n > MReader[r].len
      return zr_mr_bail(r)
    end
    h = zr_hash_new()
    zr_ary_push(objects, h)
    i = 0
    while i < n
      k = zr_mr_value(r, objects, symbols)
      if k == QUNDEF
        return k
      end
      if !zr_symbol_p(k) && !zr_fixnum_p(k) && (zr_special_p(k) || zr_type(k) != T_STRING)
        return zr_mr_bail(r)
      end
      v = zr_mr_value(r, objects, symbols)
      if v == QUNDEF
        return v
      end
      if zr_hash_store(h, k, v) == QUNDEF
        return Machine.value(QUNDEF)
      end
      i += 1
    end
    h
  end

  # `I`: a value and the ivars after it. A string gets its encoding from
  # `E` (true is UTF-8, false is US-ASCII). Any value can get an `@name`.
  # All other cases go to the Ruby reader: a named encoding, a regexp or a
  # `_load` payload with ivars, a symbol with an encoding, and ruby's own
  # hidden names.
  #: (ptr, value, value) -> value
  def zr_mr_ivars(r, objects, symbols)
    pos = MReader[r].pos
    if pos >= MReader[r].len
      return zr_mr_bail(r)
    end
    inner = Machine.u8(Machine.load8(MReader[r].bytes + pos, 0))
    if inner != MR_STRING && inner != MR_ARRAY && inner != MR_HASH && inner != MR_OBJECT && inner != MR_STRUCT && inner != MR_FLOAT
      return zr_mr_bail(r)
    end
    v = zr_mr_value(r, objects, symbols)
    if v == QUNDEF
      return v
    end
    n = zr_mr_long(r)
    if n < 0
      return zr_mr_bail(r)
    end
    i = 0
    while i < n
      id = zr_mr_symbol(r, symbols)
      if id < 0
        return zr_mr_bail(r)
      end
      item = zr_mr_value(r, objects, symbols)
      if item == QUNDEF
        return item
      end
      if id == Machine.id(:E)
        if zr_special_p(v) || zr_type(v) != T_STRING
          return zr_mr_bail(r)
        end
        zr_str_set_index(v, item == QTRUE ? ENC_UTF8 : ENC_USASCII)
      elsif zr_ivar_id_visible_p(id)
        if zr_ivar_set(v, id, item) == QUNDEF
          return Machine.value(QUNDEF)
        end
      else
        return zr_mr_bail(r)
      end
      i += 1
    end
    v
  end

  # `o`: a plain object of a class with the ordinary allocator. The reader
  # sets its ivars in order. A Range or a Set is built from its parts, and
  # an exception has special parts, so these go to the Ruby reader.
  #: (ptr, value, value) -> value
  def zr_mr_object(r, objects, symbols)
    klass = zr_mr_named_class(r, symbols)
    if klass == QUNDEF
      return zr_mr_bail(r)
    end
    if zr_alloc_kind(klass) != ALLOC_OBJECT || zr_class_inherits(klass, zr_global(G_RANGE)) || zr_mr_set_p(klass)
      return zr_mr_bail(r)
    end
    built = zr_class_allocate(klass)
    if built == QUNDEF
      return built
    end
    zr_ary_push(objects, built)
    n = zr_mr_long(r)
    if n < 0
      return zr_mr_bail(r)
    end
    i = 0
    while i < n
      id = zr_mr_symbol(r, symbols)
      if id < 0 || !zr_ivar_id_visible_p(id)
        return zr_mr_bail(r)
      end
      v = zr_mr_value(r, objects, symbols)
      if v == QUNDEF
        return v
      end
      if zr_ivar_set(built, id, v) == QUNDEF
        return Machine.value(QUNDEF)
      end
      i += 1
    end
    built
  end

  # Whether `klass` is Set or a subclass of it. The core defines Set in
  # Ruby.
  #: (value) -> bool
  def zr_mr_set_p(klass)
    set = zr_const_lookup_at(zr_global(G_OBJECT), Machine.id(:Set))
    if set == QUNDEF || zr_special_p(set) || zr_type(set) != T_CLASS
      return false
    end
    zr_class_inherits(klass, set)
  end

  # Returns the class that a symbol refers to, from the name in the
  # document.
  #: (ptr, value) -> value
  def zr_mr_named_class(r, symbols)
    id = zr_mr_symbol(r, symbols)
    if id < 0
      return Machine.value(QUNDEF)
    end
    zr_mr_class(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
  end

  # `S`: a struct. The reader stores its values by member without the
  # member writers, as marshal.c does. A Data value is frozen and is built
  # in a different way, and a member that the class does not have is an
  # error. Both cases go to the Ruby reader.
  #: (ptr, value, value) -> value
  def zr_mr_struct(r, objects, symbols)
    klass = zr_mr_named_class(r, symbols)
    if klass == QUNDEF || zr_alloc_kind(klass) != ALLOC_OBJECT
      return zr_mr_bail(r)
    end
    members = zr_mr_members(klass)
    if members == QNIL || zr_mr_data_p(klass)
      return zr_mr_bail(r)
    end
    built = zr_class_allocate(klass)
    if built == QUNDEF
      return built
    end
    zr_ary_push(objects, built)
    values = zr_struct_values_new(built)
    if values == QUNDEF
      return values
    end
    n = zr_mr_long(r)
    if n < 0
      return zr_mr_bail(r)
    end
    i = 0
    while i < n
      id = zr_mr_symbol(r, symbols)
      if id < 0
        return zr_mr_bail(r)
      end
      at = zr_mr_member_index(members, id)
      if at < 0
        return zr_mr_bail(r)
      end
      v = zr_mr_value(r, objects, symbols)
      if v == QUNDEF
        return v
      end
      if zr_ary_store(values, at, v) == QUNDEF
        return Machine.value(QUNDEF)
      end
      i += 1
    end
    built
  end

  # Returns the members of a struct class, from the nearest class that has
  # them, or nil for a class that is not a struct.
  #: (value) -> value
  def zr_mr_members(klass)
    k = klass
    while k != QNIL
      if zr_special_p(k) || zr_type(k) != T_CLASS
        return Machine.value(QNIL)
      end
      members = zr_ivar_get(k, Machine.id(:__members__))
      if members != QNIL
        return members
      end
      k = RClass[k].superclass
    end
    Machine.value(QNIL)
  end

  #: (value, word) -> word
  def zr_mr_member_index(members, id)
    n = RArray[members].len
    i = 0
    while i < n
      if zr_ary_at(members, i) == zr_sym(id)
        return i
      end
      i += 1
    end
    0 - 1
  end

  # Whether `klass` is a subclass of Data. The core defines Data in Ruby.
  #: (value) -> bool
  def zr_mr_data_p(klass)
    data = zr_const_lookup_at(zr_global(G_OBJECT), Machine.id(:Data))
    if data == QUNDEF || zr_special_p(data) || zr_type(data) != T_CLASS
      return false
    end
    zr_class_inherits(klass, data)
  end
end
