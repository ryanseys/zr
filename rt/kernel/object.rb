# Objects: a class and an ivar table (id, value rows) outside the
# arena; a class or module keeps the same table in its extension.
# Reflection, identity, inspect and p live here too.
Machine.struct :IvTab, rows: Ptr, len: Word, cap: Word
Machine.struct :IvEntry, id: Word, value: Value
Machine.struct :RObject, basic: RBasic, iv: IvTab

sig [Ptr] => Void
machine def zr_ivtab_init(t)
  IvTab.set_rows(t, 0)
  IvTab.set_len(t, 0)
  IvTab.set_cap(t, 0)
end

# The ivar table of `v`, or 0 when its kind carries none.
sig [Value] => Ptr
machine def zr_ivtab(v)
  if zr_special_p(v)
    return 0
  end
  t = zr_type(v)
  if t == T_OBJECT
    RObject.iv(v)
  elsif t == T_CLASS || t == T_MODULE
    ClassExt.iv(RClass.ext(v))
  else
    0
  end
end

sig [Ptr] => Void
machine def zr_mark_ivtab(t)
  n = IvTab.len(t)
  i = 0
  while i < n
    zr_mark(IvEntry.value(IvTab.rows(t) + (i * IvEntry.size)))
    i += 1
  end
end

sig [Ptr] => Void
machine def zr_release_ivtab(t)
  if IvTab.rows(t) != 0
    free(IvTab.rows(t))
  end
end

sig [Value] => Value
machine def zr_obj_alloc(klass)
  o = zr_alloc(T_OBJECT, klass)
  zr_ivtab_init(RObject.iv(o))
  o
end

# The row for `id` in the table `t`, or 0.
sig [Ptr, Word] => Ptr
machine def zr_ivtab_row(t, id)
  n = IvTab.len(t)
  i = 0
  while i < n
    e = IvTab.rows(t) + (i * IvEntry.size)
    if IvEntry.id(e) == id
      return e
    end
    i += 1
  end
  0
end

# The value for `id` in the table, or undef.
sig [Ptr, Word] => Value
machine def zr_ivtab_get(t, id)
  e = zr_ivtab_row(t, id)
  if e == 0
    return Machine.value(QUNDEF)
  end
  IvEntry.value(e)
end

sig [Value, Word] => Value
machine def zr_ivar_defined(obj, id)
  t = zr_ivtab(obj)
  if t == 0
    return Machine.value(QFALSE)
  end
  zr_bool(zr_ivtab_row(t, id) != 0)
end

sig [Value, Word] => Value
machine def zr_method_defined(recv, id)
  zr_bool(zr_find_method(zr_class_of(recv), id) != 0)
end

# A receiver with no table reads nil.
sig [Value, Word] => Value
machine def zr_ivar_get(obj, id)
  t = zr_ivtab(obj)
  if t == 0
    return Machine.value(QNIL)
  end
  v = zr_ivtab_get(t, id)
  if v == QUNDEF
    return Machine.value(QNIL)
  end
  v
end

sig [Value, Word, Value] => Value
machine def zr_ivar_set(obj, id, v)
  t = zr_ivtab(obj)
  if t == 0
    zr_bug(Machine.bytes("an ivar on an Integer, Symbol, String or Array is not implemented yet\n"), 70)
  end
  zr_ivtab_set(t, id, v)
  v
end

sig [Ptr, Word, Value] => Void
machine def zr_ivtab_set(t, id, v)
  e = zr_ivtab_row(t, id)
  if e == 0
    n = IvTab.len(t)
    if n == IvTab.cap(t)
      cap = n * 2
      if cap < 4
        cap = 4
      end
      rows = malloc(cap * IvEntry.size)
      if IvTab.rows(t) != 0
        zr_memcpy(rows, IvTab.rows(t), n * IvEntry.size)
        free(IvTab.rows(t))
      end
      IvTab.set_rows(t, rows)
      IvTab.set_cap(t, cap)
    end
    e = IvTab.rows(t) + (n * IvEntry.size)
    IvEntry.set_id(e, id)
    IvTab.set_len(t, n + 1)
  end
  IvEntry.set_value(e, v)
end

# A Range is a plain object of class Range with three ivars; its
# methods are the core library's.
G_RANGE = 12

sig [Value, Value, Word] => Value
machine def zr_range_new(low, high, excl)
  r = zr_obj_alloc(zr_global(G_RANGE))
  zr_ivar_set(r, Machine.id(:@begin), low)
  zr_ivar_set(r, Machine.id(:@end), high)
  zr_ivar_set(r, Machine.id(:@excl), zr_bool(excl != 0))
  r
end

# `Class#new`: allocate the shape the class's builtin ancestor gives,
# then `initialize` with the arguments.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_new_instance(recv, argc, argv, cref, blk)
  if zr_class_inherits(recv, zr_global(G_EXCEPTION))
    o = zr_exc_new(recv, Machine.value(QNIL))
  elsif zr_class_inherits(recv, zr_global(G_ARRAY))
    o = zr_ary_new(4)
    RBasic.set_klass(o, recv)
  elsif zr_class_inherits(recv, zr_global(G_HASH))
    o = zr_hash_new()
    RBasic.set_klass(o, recv)
  elsif zr_class_inherits(recv, zr_global(G_STRING))
    o = zr_str_new(Machine.bytes(""), 0)
    RBasic.set_klass(o, recv)
  elsif zr_class_inherits(recv, zr_global(G_INTEGER)) || zr_class_inherits(recv, zr_global(G_SYMBOL)) || zr_class_inherits(recv, zr_global(G_NIL)) || zr_class_inherits(recv, zr_global(G_TRUE)) || zr_class_inherits(recv, zr_global(G_FALSE))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefined method 'new' for class "), 33)
    zr_buf_str(b, RClass.name(recv))
    return zr_raise_buf(zr_global(G_NO_METHOD_ERROR), b)
  else
    o = zr_obj_alloc(recv)
  end
  r = zr_send_blk(o, Machine.id(:initialize), argc, argv, blk)
  return r if r == QUNDEF
  o
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_initialize(recv, argc, argv, cref, blk)
  Machine.value(QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_class(recv, argc, argv, cref, blk)
  zr_real_class(recv)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_singleton_class(recv, argc, argv, cref, blk)
  zr_singleton_class(recv)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_is_a(recv, argc, argv, cref, blk)
  k = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(k) || (zr_type(k) != T_CLASS && zr_type(k) != T_MODULE)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("class or module required"), 24)
  end
  zr_bool(zr_is_a(recv, k))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_instance_of(recv, argc, argv, cref, blk)
  zr_bool(zr_real_class(recv) == Machine.value(Machine.load64(argv, 0)))
end

# `Object#eql?`: identity; `Object#hash`: a number the identity gives.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_eql_p(recv, argc, argv, cref, blk)
  zr_bool(recv == Machine.value(Machine.load64(argv, 0)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_hash(recv, argc, argv, cref, blk)
  zr_fix((Machine.word(recv) >> 3) & 4611686018427387903)
end

# `String#hash`: FNV-1a over the bytes, kept in the fixnum range.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_hash(recv, argc, argv, cref, blk)
  h = 1469598103934665603
  i = 0
  while i < RString.len(recv)
    h = (h ^ Machine.word(Machine.load8(RString.ptr(recv) + i, 0))) * 1099511628211
    i += 1
  end
  zr_fix(h & 4611686018427387903)
end

# `Object#send`: the method named by the first argument, with the rest.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_send(recv, argc, argv, cref, blk)
  if argc == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no method name given"), 20)
  end
  name = Machine.value(Machine.load64(argv, 0))
  if !zr_special_p(name) && zr_type(name) == T_STRING
    name = zr_sym(zr_intern(RString.ptr(name), RString.len(name)))
  end
  unless zr_symbol_p(name)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    s = zr_send(name, Machine.id(:inspect), 0, 0)
    return s if s == QUNDEF
    zr_buf_str(b, s)
    zr_buf_push(b, Machine.bytes(" is not a symbol nor a string"), 29)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  zr_send_blk(recv, zr_sym2id(name), argc - 1, argv + 8, blk)
end

# `public_send`: as `send`, with visibility applied.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_public_send(recv, argc, argv, cref, blk)
  if argc == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no method name given"), 20)
  end
  name = Machine.value(Machine.load64(argv, 0))
  unless zr_symbol_p(name)
    zr_bug(Machine.bytes("public_send with a String name is not implemented yet\n"), 54)
  end
  zr_call_blk(recv, zr_sym2id(name), argc - 1, argv + 8, blk)
end

# `Object#===`: `==`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_eqq(recv, argc, argv, cref, blk)
  zr_send(recv, Machine.id(:==), 1, argv)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_nil_p(recv, argc, argv, cref, blk)
  zr_bool(recv == QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_eq(recv, argc, argv, cref, blk)
  zr_bool(recv == Machine.value(Machine.load64(argv, 0)))
end

# `!=` asks `==`, so a class that defines `==` gets `!=` for free.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_ne(recv, argc, argv, cref, blk)
  r = zr_send(recv, Machine.id(:==), 1, argv)
  return r if r == QUNDEF
  zr_bool(r == QNIL || r == QFALSE)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_respond_to(recv, argc, argv, cref, blk)
  if argc < 1 || argc > 2
    return zr_wrong_arity_range(argc, 1, 2)
  end
  m = Machine.value(Machine.load64(argv, 0))
  if !zr_special_p(m) && zr_type(m) == T_STRING
    m = zr_sym(zr_intern(RString.ptr(m), RString.len(m)))
  end
  unless zr_symbol_p(m)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    s = zr_send(m, Machine.id(:inspect), 0, 0)
    return s if s == QUNDEF
    zr_buf_str(b, s)
    zr_buf_push(b, Machine.bytes(" is not a symbol nor a string"), 29)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  e = zr_find_method(zr_class_of(recv), zr_sym2id(m))
  if e == 0
    return Machine.value(QFALSE)
  end
  all = argc == 2 && Machine.value(Machine.load64(argv, 8)) != QNIL && Machine.value(Machine.load64(argv, 8)) != QFALSE
  zr_bool(all || MEntry.vis(e) == VIS_PUBLIC)
end

# `#<Name:0x...` with sixteen hex digits, into `b`.
sig [Ptr, Value] => Void
machine def zr_buf_obj_head(b, obj)
  zr_buf_push(b, Machine.bytes("#<"), 2)
  zr_buf_str(b, zr_class_name_of(obj))
  zr_buf_push(b, Machine.bytes(":0x"), 3)
  w = Machine.word(obj)
  i = 0
  while i < 16
    d = (w >> (60 - (i * 4))) & 15
    if d < 10
      zr_buf_byte(b, 48 + d)
    else
      zr_buf_byte(b, 87 + d)
    end
    i += 1
  end
end

# `#<Name:0x... @a=1, @b=2>`; the ivar values' `inspect` may run Ruby,
# so the table is re-read after each.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_inspect(recv, argc, argv, cref, blk)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_obj_head(b, recv)
  i = 0
  while i < IvTab.len(RObject.iv(recv))
    e = IvTab.rows(RObject.iv(recv)) + (i * IvEntry.size)
    zr_buf_push(b, i == 0 ? Machine.bytes(" ") : Machine.bytes(", "), i == 0 ? 1 : 2)
    zr_buf_sym(b, IvEntry.id(e))
    zr_buf_byte(b, 61)
    s = zr_send(IvEntry.value(e), Machine.id(:inspect), 0, 0)
    if s == QUNDEF
      free(Buf.ptr(b))
      return s
    end
    zr_buf_str(b, s)
    i += 1
  end
  zr_buf_byte(b, 62)
  zr_buf_take(b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_nil_inspect(recv, argc, argv, cref, blk)
  zr_str_new(Machine.bytes("nil"), 3)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_inspect(recv, argc, argv, cref, blk)
  zr_int_to_s(recv, argc, argv, cref, blk)
end

sig [Word] => Bool
machine def zr_ident_byte_p(c)
  (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c >= 128
end

# `:name`, quoted when the name is not a plain identifier or operator.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_sym_inspect(recv, argc, argv, cref, blk)
  id = zr_sym2id(recv)
  p = zr_symbol_name_ptr(id)
  n = zr_symbol_name_len(id)
  plain = n > 0
  i = 0
  while i < n
    c = Machine.word(Machine.load8(p + i, 0))
    unless zr_ident_byte_p(c) || (i == n - 1 && (c == 63 || c == 33 || c == 61)) || (i == 0 && c == 64)
      plain = false
    end
    i += 1
  end
  if Machine.word(Machine.load8(p, 0)) >= 48 && Machine.word(Machine.load8(p, 0)) <= 57
    plain = false
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_byte(b, 58)
  if plain || zr_operator_name_p(p, n)
    zr_buf_push(b, p, n)
  else
    zr_buf_str_escaped(b, p, n)
  end
  zr_buf_take(b)
end

sig [Ptr, Word] => Bool
machine def zr_operator_name_p(p, n)
  if n == 1
    c = Machine.word(Machine.load8(p, 0))
    c == 43 || c == 45 || c == 42 || c == 47 || c == 37 || c == 60 || c == 62 || c == 33 || c == 38 || c == 124 || c == 94 || c == 126
  elsif n == 2
    c = Machine.word(Machine.load8(p, 0))
    d = Machine.word(Machine.load8(p, 1))
    (c == 60 && (d == 60 || d == 61)) || (c == 62 && (d == 62 || d == 61)) || (c == 61 && (d == 61 || d == 126)) || (c == 33 && (d == 61 || d == 126)) || (c == 42 && d == 42) || (c == 91 && d == 93)
  elsif n == 3
    c = Machine.word(Machine.load8(p, 0))
    d = Machine.word(Machine.load8(p, 1))
    e = Machine.word(Machine.load8(p, 2))
    (c == 60 && d == 61 && e == 62) || (c == 61 && d == 61 && e == 61) || (c == 91 && d == 93 && e == 61)
  else
    false
  end
end

# A double-quoted, escaped rendering of `n` bytes, as String#inspect.
sig [Ptr, Ptr, Word] => Void
machine def zr_buf_str_escaped(b, p, n)
  zr_buf_byte(b, 34)
  i = 0
  while i < n
    c = Machine.word(Machine.load8(p + i, 0))
    if c == 34 || c == 92
      zr_buf_byte(b, 92)
      zr_buf_byte(b, c)
    elsif c == 10
      zr_buf_push(b, Machine.bytes("\\n"), 2)
    elsif c == 9
      zr_buf_push(b, Machine.bytes("\\t"), 2)
    elsif c == 13
      zr_buf_push(b, Machine.bytes("\\r"), 2)
    elsif c == 27
      zr_buf_push(b, Machine.bytes("\\e"), 2)
    elsif c == 7
      zr_buf_push(b, Machine.bytes("\\a"), 2)
    elsif c == 8
      zr_buf_push(b, Machine.bytes("\\b"), 2)
    elsif c == 12
      zr_buf_push(b, Machine.bytes("\\f"), 2)
    elsif c == 11
      zr_buf_push(b, Machine.bytes("\\v"), 2)
    elsif c == 35 && i + 1 < n && (Machine.word(Machine.load8(p + i, 1)) == 123 || Machine.word(Machine.load8(p + i, 1)) == 36 || Machine.word(Machine.load8(p + i, 1)) == 64)
      zr_buf_push(b, Machine.bytes("\\#"), 2)
    elsif c < 32 || c == 127
      zr_buf_push(b, Machine.bytes("\\x"), 2)
      zr_buf_byte(b, zr_hex_digit(c >> 4))
      zr_buf_byte(b, zr_hex_digit(c & 15))
    else
      zr_buf_byte(b, c)
    end
    i += 1
  end
  zr_buf_byte(b, 34)
end

sig [Word] => Word
machine def zr_hex_digit(d)
  if d < 10
    48 + d
  else
    55 + d
  end
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_inspect(recv, argc, argv, cref, blk)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_str_escaped(b, RString.ptr(recv), RString.len(recv))
  zr_buf_take(b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_true_inspect(recv, argc, argv, cref, blk)
  zr_str_new(Machine.bytes("true"), 4)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_false_inspect(recv, argc, argv, cref, blk)
  zr_str_new(Machine.bytes("false"), 5)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_name(recv, argc, argv, cref, blk)
  RClass.name(recv)
end

# An anonymous class prints as `#<Class:0x...>`, a singleton class as
# `#<Class:` around what it is attached to.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_to_s(recv, argc, argv, cref, blk)
  if zr_singleton_p(recv)
    inner = zr_send(RClass.attached(recv), Machine.id(:inspect), 0, 0)
    return inner if inner == QUNDEF
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("#<Class:"), 8)
    zr_buf_str(b, inner)
    zr_buf_byte(b, 62)
    return zr_buf_take(b)
  end
  if RClass.name(recv) == QNIL
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_obj_head(b, recv)
    zr_buf_byte(b, 62)
    return zr_buf_take(b)
  end
  RClass.name(recv)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_superclass(recv, argc, argv, cref, blk)
  k = RClass.superclass(recv)
  while k != QNIL && zr_type(k) == T_ICLASS
    k = RClass.superclass(k)
  end
  k
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_message(recv, argc, argv, cref, blk)
  m = RException.message(recv)
  if m == QNIL
    return zr_class_name_of(recv)
  end
  m
end

# `#<Klass: message>`, or the class name alone when the message is empty.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_inspect(recv, argc, argv, cref, blk)
  m = RException.message(recv)
  if m == QNIL
    m = zr_class_name_of(recv)
  end
  if RString.len(m) == 0
    return zr_class_name_of(recv)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("#<"), 2)
  zr_buf_str(b, zr_class_name_of(recv))
  zr_buf_push(b, Machine.bytes(": "), 2)
  zr_buf_str(b, m)
  zr_buf_byte(b, 62)
  zr_buf_take(b)
end

# `Exception#initialize(message = nil)`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_initialize(recv, argc, argv, cref, blk)
  if argc > 0
    RException.set_message(recv, Machine.value(Machine.load64(argv, 0)))
  end
  Machine.value(QNIL)
end

# `p`: each argument's inspect on its own line; answers the argument,
# or an Array of several.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_p(recv, argc, argv, cref, blk)
  i = 0
  while i < argc
    s = zr_send(Machine.value(Machine.load64(argv + (i * 8), 0)), Machine.id(:inspect), 0, 0)
    return s if s == QUNDEF
    zr_write_out(RString.ptr(s), RString.len(s))
    zr_write_out(Machine.bytes("\n"), 1)
    i += 1
  end
  if argc == 0
    return Machine.value(QNIL)
  end
  if argc > 1
    return zr_ary_of(argc, argv)
  end
  Machine.value(Machine.load64(argv, 0))
end

# `attr_reader`, `attr_writer`, `attr_accessor`: one entry per name.
sig [Value, Word, Ptr, Word] => Value
machine def zr_attr(klass, argc, argv, which)
  i = 0
  while i < argc
    name = Machine.value(Machine.load64(argv + (i * 8), 0))
    unless zr_symbol_p(name)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("is not a symbol nor a string"), 28)
    end
    id = zr_sym2id(name)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_byte(b, 64)
    zr_buf_sym(b, id)
    ivar = zr_intern(Buf.ptr(b), Buf.len(b))
    if which != 2
      zr_define_method(klass, id, Machine.ptr(ivar), 0, KIND_ATTR_READER, 0, Machine.value(QNIL))
    end
    if which != 1
      zr_buf_byte(b, 61)
      setter = zr_intern(Buf.ptr(b) + 1, Buf.len(b) - 1)
      zr_define_method(klass, setter, Machine.ptr(ivar), 1, KIND_ATTR_WRITER, 0, Machine.value(QNIL))
    end
    free(Buf.ptr(b))
    i += 1
  end
  Machine.value(QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_attr_reader(recv, argc, argv, cref, blk)
  zr_attr(recv, argc, argv, 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_attr_writer(recv, argc, argv, cref, blk)
  zr_attr(recv, argc, argv, 2)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_attr_accessor(recv, argc, argv, cref, blk)
  zr_attr(recv, argc, argv, 3)
end
