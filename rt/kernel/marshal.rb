# Marshal's reader for the kinds a dump is mostly made of -- nil, the
# booleans, fixnums, floats, symbols and their links, strings with
# their encoding, arrays, hashes, plain objects and structs, a `_load`
# payload (an Encoding, mostly), a bignum that fits a fixnum, and links
# to any of them. Anything else (`marshal_load`, a class or module, a
# regexp, a wider bignum, an extended or subclassed value, a hash with
# a default, an object of a class with an allocator of its own) makes
# the whole read fall back to the Ruby reader
# (rt/core/marshal.rb), which reads the document from its start. The
# two read the same bytes to the same values; this one reads them at
# the speed of a copy, which is what a cache of parses or of compiled
# units is read at.
#
# The reader's state, on the stack: the bytes, how many, where it is,
# and whether it has given up. What it has made -- the object and
# symbol tables -- rides in two Arrays the caller holds, since a slot
# on the stack roots nothing.
Machine.struct :MReader, bytes: Ptr, len: Word, pos: Word, bail: Word

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

# `Marshal.load(bytes)` for a String. Where the Ruby reader must read
# it instead -- a document of another format version, one cut short,
# or one holding a kind this reader leaves to Ruby -- the answer is nil
# and zr_marshal_bailed_p says so; undef is a raise, which the caller
# passes on.
sig [Value] => Value
machine def zr_marshal_load_fast(src)
  Machine.store64(Machine.static(:marshal_bailed, 8), 0, 0)
  r = Machine.slot(MReader.size)
  MReader.set_bytes(r, RString.ptr(src))
  MReader.set_len(r, RString.len(src))
  MReader.set_pos(r, 2)
  MReader.set_bail(r, 0)
  if RString.len(src) < 2 || Machine.word(Machine.load8(RString.ptr(src), 0)) != 4 || Machine.word(Machine.load8(RString.ptr(src), 1)) > 8
    zr_mr_bail(r)
    return Machine.value(QNIL)
  end
  objects = zr_ary_new(64)
  symbols = zr_ary_new(64)
  v = zr_mr_value(r, objects, symbols)
  if MReader.bail(r) != 0
    return Machine.value(QNIL)
  end
  if v == QUNDEF
    return v
  end
  # Bytes past the value are ruby's business too: the Ruby reader
  # answers what ruby answers for them.
  if MReader.pos(r) != MReader.len(r)
    zr_mr_bail(r)
    return Machine.value(QNIL)
  end
  v
end

# Whether the fast reader gave the document up, rather than read it or
# raised.
sig [] => Value
machine def zr_marshal_bailed_p
  Machine.value(Machine.load64(Machine.static(:marshal_bailed, 8), 0) != 0 ? QTRUE : QFALSE)
end

# The reader gives up: undef, with the reason kept for the caller.
sig [Ptr] => Value
machine def zr_mr_bail(r)
  MReader.set_bail(r, 1)
  Machine.store64(Machine.static(:marshal_bailed, 8), 0, 1)
  Machine.value(QUNDEF)
end

# The next byte, or -1 past the end, which is a document cut short and
# so the Ruby reader's to refuse.
sig [Ptr] => Word
machine def zr_mr_byte(r)
  pos = MReader.pos(r)
  if pos >= MReader.len(r)
    zr_mr_bail(r)
    return 0 - 1
  end
  MReader.set_pos(r, pos + 1)
  Machine.word(Machine.load8(MReader.bytes(r) + pos, 0))
end

# The packed integer: one byte for a small number, else a count byte
# and that many bytes of it, least significant first. -1 for a number
# cut short, which no packed count or index is.
sig [Ptr] => Word
machine def zr_mr_long(r)
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

# `n` bytes of text from where the reader stands, as a pointer, or 0
# past the end; the reader steps over them.
sig [Ptr, Word] => Ptr
machine def zr_mr_text(r, n)
  pos = MReader.pos(r)
  if n < 0 || pos + n > MReader.len(r)
    return 0
  end
  MReader.set_pos(r, pos + n)
  MReader.bytes(r) + pos
end

# Whether `n` bytes at `p` are all ASCII. A symbol with a byte past
# ASCII has an encoding of its own to intern under, which the Ruby
# reader decides.
sig [Ptr, Word] => Bool
machine def zr_mr_ascii_p(p, n)
  i = 0
  while i < n
    if Machine.word(Machine.load8(p + i, 0)) > 127
      return false
    end
    i += 1
  end
  true
end

# A symbol, new or linked, as its id; -1 for anything else.
sig [Ptr, Value] => Word
machine def zr_mr_symbol(r, symbols)
  tag = zr_mr_byte(r)
  if tag == MR_SYMLINK
    i = zr_mr_long(r)
    if i < 0 || i >= RArray.len(symbols)
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

# The class `path` names ("Prism::CallNode"), walked from Object one
# component at a time; undef for a path that names nothing or names
# something that is not a class.
sig [Ptr, Word] => Value
machine def zr_mr_class(p, n)
  scope = zr_global(G_OBJECT)
  at = 0
  while at < n
    stop = at
    while stop < n && Machine.word(Machine.load8(p + stop, 0)) != 58
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
      if at + 2 > n || Machine.word(Machine.load8(p + at + 1, 0)) != 58
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

# One value. Undef is a bail or a raise (`MReader.bail` tells them
# apart); every value that has a link slot takes it before its parts,
# as marshal.c registers it.
sig [Ptr, Value, Value] => Value
machine def zr_mr_value(r, objects, symbols)
  tag = zr_mr_byte(r)
  if tag == MR_OBJECT
    return zr_mr_object(r, objects, symbols)
  elsif tag == MR_SYMLINK
    i = zr_mr_long(r)
    if i < 0 || i >= RArray.len(symbols)
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
    if i < 0 || i >= RArray.len(objects)
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

# `l`: a sign, a count of 16-bit words, and the words least
# significant first. ruby writes every integer past 32 bits this way,
# a prism location among them, so most are fixnums here; one past a
# fixnum is the core's Bignum to build, which is Ruby's.
sig [Ptr, Value] => Value
machine def zr_mr_bignum(r, objects)
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
    value = (value << 8) | Machine.word(Machine.load8(p + i, 0))
  end
  if value < 0 || value > 4611686018427387903
    return zr_mr_bail(r)
  end
  v = zr_fix(sign == 45 ? 0 - value : value)
  zr_ary_push(objects, v)
  v
end

# `u`: a class's `_load` over the bytes it dumped. An Encoding's
# `_load` answers its name, which the encoding is found by, as the
# Ruby reader has it; a payload with ivars of its own is Ruby's.
sig [Ptr, Value, Value] => Value
machine def zr_mr_user_dump(r, objects, symbols)
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

# The bytes of a string, binary until an ivar says its encoding.
sig [Ptr] => Value
machine def zr_mr_string(r)
  n = zr_mr_long(r)
  p = zr_mr_text(r, n)
  if p == 0
    return Machine.value(QUNDEF)
  end
  s = zr_str_new(p, n)
  zr_str_set_index(s, ENC_BINARY)
  s
end

# A float's text, which strtod reads as ruby's writer wrote it: a
# decimal, or "inf", "-inf" and "nan".
sig [Ptr, Value] => Value
machine def zr_mr_float(r, objects)
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

sig [Ptr, Value, Value] => Value
machine def zr_mr_array(r, objects, symbols)
  n = zr_mr_long(r)
  if n < 0 || n > MReader.len(r)
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

# A hash with no default. A key that runs Ruby code to hash itself (an
# object with its own `hash`) is left to the Ruby reader.
sig [Ptr, Value, Value] => Value
machine def zr_mr_hash(r, objects, symbols)
  n = zr_mr_long(r)
  if n < 0 || n > MReader.len(r)
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

# `I`: a value and the ivars after it. A string takes its encoding from
# `E` (true is UTF-8, false US-ASCII); any value takes an `@name`; the
# rest -- a named encoding, a regexp or a `_load` payload with ivars,
# a symbol with an encoding, ruby's own hidden names -- is Ruby's.
sig [Ptr, Value, Value] => Value
machine def zr_mr_ivars(r, objects, symbols)
  pos = MReader.pos(r)
  if pos >= MReader.len(r)
    return zr_mr_bail(r)
  end
  inner = Machine.word(Machine.load8(MReader.bytes(r) + pos, 0))
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

# `o`: a plain object of a class with the ordinary allocator, its ivars
# set as they come. A Range or a Set is built from its parts, an
# exception has parts of its own: those are Ruby's.
sig [Ptr, Value, Value] => Value
machine def zr_mr_object(r, objects, symbols)
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

# Whether `klass` is Set or under it, which the core defines in Ruby.
sig [Value] => Bool
machine def zr_mr_set_p(klass)
  set = zr_const_lookup_at(zr_global(G_OBJECT), Machine.id(:Set))
  if set == QUNDEF || zr_special_p(set) || zr_type(set) != T_CLASS
    return false
  end
  zr_class_inherits(klass, set)
end

# The class a symbol names, from the reader's own name.
sig [Ptr, Value] => Value
machine def zr_mr_named_class(r, symbols)
  id = zr_mr_symbol(r, symbols)
  if id < 0
    return Machine.value(QUNDEF)
  end
  zr_mr_class(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
end

# `S`: a struct, its values stored by member, as marshal.c stores them
# without the members' writers. A Data value is frozen and built
# otherwise; a member the class does not have is an error: both are
# Ruby's.
sig [Ptr, Value, Value] => Value
machine def zr_mr_struct(r, objects, symbols)
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

# The members of a struct class, from the nearest class holding them,
# or nil for a class that is no struct.
sig [Value] => Value
machine def zr_mr_members(klass)
  k = klass
  while k != QNIL
    if zr_special_p(k) || zr_type(k) != T_CLASS
      return Machine.value(QNIL)
    end
    members = zr_ivar_get(k, Machine.id(:__members__))
    if members != QNIL
      return members
    end
    k = RClass.superclass(k)
  end
  Machine.value(QNIL)
end

sig [Value, Word] => Word
machine def zr_mr_member_index(members, id)
  n = RArray.len(members)
  i = 0
  while i < n
    if zr_ary_at(members, i) == zr_sym(id)
      return i
    end
    i += 1
  end
  0 - 1
end

# Whether `klass` is under Data, which the core defines in Ruby.
sig [Value] => Bool
machine def zr_mr_data_p(klass)
  data = zr_const_lookup_at(zr_global(G_OBJECT), Machine.id(:Data))
  if data == QUNDEF || zr_special_p(data) || zr_type(data) != T_CLASS
    return false
  end
  zr_class_inherits(klass, data)
end
