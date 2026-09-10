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

# The ivar table of `v`, or 0 when it has none yet: an object's or a
# class's own, else the one kept beside the arena.
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
  elsif (RBasic.flags(v) & FL_EXIVAR) != 0
    zr_exivar_tab(v)
  else
    0
  end
end

# The table a write goes to: made now when the kind has none of its
# own. A special constant is frozen.
sig [Value] => Ptr
machine def zr_ivtab_for_write(v)
  t = zr_ivtab(v)
  if t != 0
    return t
  end
  if zr_special_p(v)
    return 0
  end
  zr_exivar_tab_for_write(v)
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

# `defined?(recv.name)`: a method the call could reach, so not a
# private one with an explicit receiver, nor a protected one from
# outside the owner.
sig [Value, Word, Bool] => Value
machine def zr_method_defined(recv, id, explicit)
  e = zr_find_method(zr_class_of(recv), id)
  if e == 0
    return zr_bool(zr_respond_to_missing_p(recv, id))
  end
  if explicit && MEntry.vis(e) == VIS_PRIVATE
    return Machine.value(QFALSE)
  end
  if explicit && MEntry.vis(e) == VIS_PROTECTED && !zr_is_a(Frame.self(Task.top(zr_task())), FrameMeta.owner(MEntry.meta(e)))
    return Machine.value(QFALSE)
  end
  Machine.value(QTRUE)
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

# A hidden instance variable: one whose name has no `@`, which
# `instance_variables` and `inspect` leave out and no Ruby name can
# reach. Struct keeps its members and values in them, as CRuby does.
sig [Value, Value] => Value
machine def zr_hidden_get(obj, name)
  zr_ivar_get(obj, zr_sym2id(name))
end

sig [Value, Value, Value] => Value
machine def zr_hidden_set(obj, name, v)
  zr_ivar_set(obj, zr_sym2id(name), v)
end

# `object_id`: a fixnum's is 2n + 1, nil's 4, true's 20, false's 0;
# a heap object's comes from a counter (8, 16, 24, ...) at its first
# call, kept in a hidden ivar. A symbol's or a flonum's is its word,
# as CRuby answers, so a symbol's differs from CRuby's by the id.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_object_id(recv, argc, argv, cref, blk)
  if zr_fixnum_p(recv)
    return zr_fix((zr_fix2long(recv) * 2) + 1)
  end
  if recv == QNIL
    return zr_fix(4)
  end
  if recv == QTRUE
    return zr_fix(20)
  end
  if recv == QFALSE
    return zr_fix(0)
  end
  if zr_special_p(recv)
    w = Machine.word(recv)
    if w >= 2305843009213693952 || w < -2305843009213693952
      zr_bug(Machine.bytes("object_id of this flonum is not implemented yet\n"), 48)
    end
    return zr_fix(w)
  end
  t = zr_ivtab_for_write(recv)
  id = zr_ivtab_get(t, Machine.id(:__object_id__))
  if id != QUNDEF
    return id
  end
  counter = Machine.static(:object_id_counter, 8)
  n = Machine.load64(counter, 0) + 8
  Machine.store64(counter, 0, n)
  id = zr_fix(n)
  zr_ivtab_set(t, Machine.id(:__object_id__), id)
  id
end

# Whether an instance variable's name shows: it starts with `@`.
sig [Word] => Bool
machine def zr_ivar_id_visible_p(id)
  Machine.word(Machine.load8(zr_symbol_name_ptr(id), 0)) == 64
end

sig [Value, Word, Value] => Value
machine def zr_ivar_set(obj, id, v)
  if zr_frozen_p(obj)
    return zr_frozen_error(obj)
  end
  t = zr_ivtab_for_write(obj)
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

# A Range is a plain frozen object of class Range with three ivars;
# its methods are the core library's.
G_RANGE = 12

sig [Value, Value, Word] => Value
machine def zr_range_new(low, high, excl)
  if low != QNIL && high != QNIL && !(zr_fixnum_p(low) && zr_fixnum_p(high))
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(high))
    c = zr_send(low, Machine.id(:<=>), 1, slot)
    return c if c == QUNDEF
    if c == QNIL
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("bad value for range"), 19)
    end
  end
  r = zr_obj_alloc(zr_global(G_RANGE))
  zr_ivar_set(r, Machine.id(:@begin), low)
  zr_ivar_set(r, Machine.id(:@end), high)
  zr_ivar_set(r, Machine.id(:@excl), zr_bool(excl != 0))
  RBasic.set_flags(r, RBasic.flags(r) | FL_FREEZE)
  r
end

# `Class#allocate`: the shape the class's builtin ancestor gives, not
# yet initialized.
sig [Value] => Value
machine def zr_class_allocate(recv)
  if recv == zr_global(G_CLASS)
    return zr_class_alloc(T_CLASS, Machine.value(QNIL), zr_global(G_CLASS))
  end
  if recv == zr_global(G_MODULE)
    return zr_module_new()
  end
  if zr_class_inherits(recv, zr_global(G_EXCEPTION))
    return zr_exc_new(recv, Machine.value(QNIL))
  end
  if zr_class_inherits(recv, zr_global(G_ARRAY))
    o = zr_ary_new(4)
  elsif zr_class_inherits(recv, zr_global(G_HASH))
    o = zr_hash_new()
  elsif zr_class_inherits(recv, zr_global(G_STRING))
    o = zr_str_new(Machine.bytes(""), 0)
  elsif zr_class_inherits(recv, zr_global(G_INTEGER)) || zr_class_inherits(recv, zr_global(G_SYMBOL)) || zr_class_inherits(recv, zr_global(G_NIL)) || zr_class_inherits(recv, zr_global(G_TRUE)) || zr_class_inherits(recv, zr_global(G_FALSE))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("allocator undefined for "), 24)
    zr_buf_class(b, recv)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  else
    return zr_obj_alloc(recv)
  end
  RBasic.set_klass(o, recv)
  o
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_allocate_m(recv, argc, argv, cref, blk)
  zr_class_allocate(recv)
end

# `Class#new`: allocate, then `initialize` with the arguments.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_new_instance(recv, argc, argv, cref, blk)
  if zr_class_inherits(recv, zr_global(G_INTEGER)) || zr_class_inherits(recv, zr_global(G_SYMBOL)) || zr_class_inherits(recv, zr_global(G_NIL)) || zr_class_inherits(recv, zr_global(G_TRUE)) || zr_class_inherits(recv, zr_global(G_FALSE))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefined method 'new' for class "), 33)
    zr_buf_class(b, recv)
    return zr_raise_buf(zr_global(G_NO_METHOD_ERROR), b)
  end
  o = zr_class_allocate(recv)
  return o if o == QUNDEF
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

# `String#hash`: FNV-1a over the bytes, and over the encoding too when
# the bytes are not all ASCII, so that two strings which do not
# compare do not share a code.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_hash(recv, argc, argv, cref, blk)
  h = 1469598103934665603
  i = 0
  while i < RString.len(recv)
    h = (h ^ Machine.word(Machine.load8(RString.ptr(recv) + i, 0))) * 1099511628211
    i += 1
  end
  if !zr_str_ascii_only(recv)
    h = (h ^ zr_str_encoding_index(recv)) * 1099511628211
  end
  zr_fix(h & 4611686018427387903)
end

# `Object#send`: the method named by the first argument, with the rest.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_send(recv, argc, argv, cref, blk)
  if argc == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no method name given"), 20)
  end
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  zr_send_blk(recv, Machine.load64(slot, 0), argc - 1, argv + 8, blk)
end

# `public_send`: as `send`, with visibility applied.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_public_send(recv, argc, argv, cref, blk)
  if argc == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no method name given"), 20)
  end
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  if blk != QNIL
    RProc.set_passed(blk, 1)
  end
  zr_dispatch(recv, Machine.load64(slot, 0), argc - 1, argv + 8, 3, blk)
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

# Whether the receiver's own `respond_to_missing?` claims `mid`.
sig [Value, Word] => Bool
machine def zr_respond_to_missing_p(recv, mid)
  e = zr_find_method(zr_class_of(recv), Machine.id(:respond_to_missing?))
  if e == 0 || MEntry.fn(e) == Machine.addr(:zr_obj_respond_to_missing)
    return false
  end
  pair = Machine.slot(16)
  Machine.store64(pair, 0, Machine.word(zr_sym(mid)))
  Machine.store64(pair, 8, QTRUE)
  r = zr_invoke(e, recv, 2, pair, Machine.value(QNIL), 0)
  r != QUNDEF && r != QNIL && r != QFALSE
end

# `Object#respond_to_missing?`: false, for a subclass to override.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_respond_to_missing(recv, argc, argv, cref, blk)
  if argc != 2
    return zr_wrong_arity(argc, 2)
  end
  Machine.value(QFALSE)
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
  all = argc == 2 && Machine.value(Machine.load64(argv, 8)) != QNIL && Machine.value(Machine.load64(argv, 8)) != QFALSE
  e = zr_find_method(zr_class_of(recv), zr_sym2id(m))
  if e == 0
    return zr_bool(zr_respond_to_missing_p(recv, zr_sym2id(m)))
  end
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
  # As rb_obj_inspect: only a plain object shows its instance
  # variables; anything else (a fixnum under a redefined Integer#inspect
  # calling super) takes the address form.
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_obj_head(b, recv)
  if zr_special_p(recv) || zr_type(recv) != T_OBJECT
    zr_buf_byte(b, 62)
    return zr_buf_take(b)
  end
  filter = zr_send(recv, Machine.id(:instance_variables_to_inspect), 0, 0)
  if filter == QUNDEF
    free(Buf.ptr(b))
    return filter
  end
  if filter != QNIL && (zr_special_p(filter) || zr_type(filter) != T_ARRAY)
    free(Buf.ptr(b))
    m = Machine.slot(Buf.size)
    zr_buf_init(m)
    zr_buf_push(m, Machine.bytes("Expected #instance_variables_to_inspect to return an Array or nil, but it returned "), 83)
    zr_buf_str(m, zr_class_name_of(filter))
    return zr_raise_buf(zr_global(G_TYPE_ERROR), m)
  end
  i = 0
  shown = 0
  while i < IvTab.len(RObject.iv(recv))
    e = IvTab.rows(RObject.iv(recv)) + (i * IvEntry.size)
    i += 1
    if zr_ivar_id_visible_p(IvEntry.id(e)) && (filter == QNIL || zr_ary_index_of(filter, zr_sym(IvEntry.id(e))) >= 0)
      zr_buf_push(b, shown == 0 ? Machine.bytes(" ") : Machine.bytes(", "), shown == 0 ? 1 : 2)
      shown += 1
      zr_buf_sym(b, IvEntry.id(e))
      zr_buf_byte(b, 61)
      s = zr_send(IvEntry.value(e), Machine.id(:inspect), 0, 0)
      if s == QUNDEF
        free(Buf.ptr(b))
        return s
      end
      zr_buf_str(b, s)
    end
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

# Whether `n` bytes are a symbol literal's plain name: an identifier
# that may end in `?`, `!` or `=`, or one with a `@`, `@@` or `$`
# sigil (then without the suffix), or an operator.
sig [Ptr, Word] => Bool
machine def zr_symname_plain_p(p, n)
  if n == 0
    return false
  end
  c = Machine.word(Machine.load8(p, 0))
  i = 0
  if c == 64
    i = 1
    if n > 1 && Machine.word(Machine.load8(p, 1)) == 64
      i = 2
    end
  elsif c == 36
    i = 1
  end
  if i > 0
    if i >= n
      return false
    end
    first = Machine.word(Machine.load8(p + i, 0))
    if first >= 48 && first <= 57
      return false
    end
    while i < n
      if !zr_ident_byte_p(Machine.word(Machine.load8(p + i, 0)))
        return false
      end
      i += 1
    end
    return true
  end
  if c >= 48 && c <= 57
    return false
  end
  if !zr_ident_byte_p(c)
    return zr_operator_name_p(p, n)
  end
  while i < n
    c = Machine.word(Machine.load8(p + i, 0))
    if !zr_ident_byte_p(c)
      return i == n - 1 && (c == 63 || c == 33 || c == 61)
    end
    i += 1
  end
  true
end

# `:name`, quoted when the name is not a plain identifier or operator.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_sym_inspect(recv, argc, argv, cref, blk)
  id = zr_sym2id(recv)
  p = zr_symbol_name_ptr(id)
  n = zr_symbol_name_len(id)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_byte(b, 58)
  if zr_symname_plain_p(p, n)
    zr_buf_push(b, p, n)
  else
    zr_buf_str_escaped(b, p, n, false)
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
    (c == 60 && (d == 60 || d == 61)) || (c == 62 && (d == 62 || d == 61)) || (c == 61 && (d == 61 || d == 126)) || (c == 33 && (d == 61 || d == 126)) || (c == 42 && d == 42) || (c == 91 && d == 93) || ((c == 43 || c == 45) && d == 64)
  elsif n == 3
    c = Machine.word(Machine.load8(p, 0))
    d = Machine.word(Machine.load8(p, 1))
    e = Machine.word(Machine.load8(p, 2))
    (c == 60 && d == 61 && e == 62) || (c == 61 && d == 61 && e == 61) || (c == 91 && d == 93 && e == 61)
  else
    false
  end
end

# The length of the valid UTF-8 sequence at `p`, or 0 when the byte
# does not start one.
sig [Ptr, Word] => Word
machine def zr_utf8_char_len(p, n)
  c = Machine.word(Machine.load8(p, 0))
  if c < 128
    return 1
  end
  len = 0
  if c >= 194 && c <= 223
    len = 2
  elsif c >= 224 && c <= 239
    len = 3
  elsif c >= 240 && c <= 244
    len = 4
  end
  if len == 0 || len > n
    return 0
  end
  i = 1
  while i < len
    d = Machine.word(Machine.load8(p + i, 0))
    if d < 128 || d > 191
      return 0
    end
    i += 1
  end
  len
end

# A double-quoted, escaped rendering of `n` bytes, as String#inspect:
# a binary string spells every high byte in hex; a text string keeps a
# valid UTF-8 character and spells the rest in hex.
sig [Ptr, Ptr, Word, Bool] => Void
machine def zr_buf_str_escaped(b, p, n, binary)
  zr_buf_byte(b, 34)
  i = 0
  while i < n
    c = Machine.word(Machine.load8(p + i, 0))
    if c >= 128
      len = binary ? 0 : zr_utf8_char_len(p + i, n - i)
      if len == 0
        zr_buf_push(b, Machine.bytes("\\x"), 2)
        zr_buf_byte(b, zr_hex_digit(c >> 4))
        zr_buf_byte(b, zr_hex_digit(c & 15))
        i += 1
      else
        zr_buf_push(b, p + i, len)
        i += len
      end
    elsif c == 34 || c == 92
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
      zr_buf_push(b, binary ? Machine.bytes("\\x") : Machine.bytes("\\u00"), binary ? 2 : 4)
      zr_buf_byte(b, zr_hex_digit(c >> 4))
      zr_buf_byte(b, zr_hex_digit(c & 15))
    else
      zr_buf_byte(b, c)
    end
    i += 1 if c < 128
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
  zr_buf_str_escaped(b, RString.ptr(recv), RString.len(recv), !zr_str_wide_p(recv))
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

# A class's name in a message, or its `#<Class:0x...>` form when it has
# none; QUNDEF when an inspect along the way raised.
sig [Ptr, Value] => Value
machine def zr_buf_class(b, klass)
  if RClass.name(klass) != QNIL && !zr_singleton_p(klass)
    zr_buf_str(b, RClass.name(klass))
    return Machine.value(QNIL)
  end
  s = zr_class_to_s(klass, 0, 0, Machine.value(QNIL), Machine.value(QNIL))
  return s if s == QUNDEF
  zr_buf_str(b, s)
  Machine.value(QNIL)
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

# The superclass past the proxies of included modules.
sig [Value] => Value
machine def zr_real_superclass(klass)
  k = RClass.superclass(klass)
  while k != QNIL && zr_type(k) == T_ICLASS
    k = RClass.superclass(k)
  end
  k
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_superclass(recv, argc, argv, cref, blk)
  zr_real_superclass(recv)
end

# `Exception#to_s`: the message, or the class name when there is none;
# a message that is not a String is `to_s`ed.
sig [Value] => Value
machine def zr_exc_to_s(recv)
  m = RException.message(recv)
  if m == QNIL
    return zr_class_name_of(recv)
  end
  if zr_special_p(m) || zr_type(m) != T_STRING
    return zr_send(m, Machine.id(:to_s), 0, 0)
  end
  m
end

# The message as it was given, nil when the class name stands in for it.
# Marshal needs the two apart.
sig [Value] => Value
machine def zr_exc_raw_message(recv)
  RException.message(recv)
end

sig [Value, Value] => Value
machine def zr_exc_set_message(recv, m)
  RException.set_message(recv, m)
  m
end

# `detailed_message`: `message (Class)`, the class after the first
# line; `unhandled exception` for an empty message.
sig [Value] => Value
machine def zr_exc_detailed_message(recv)
  m = zr_send(recv, Machine.id(:message), 0, 0)
  return m if m == QUNDEF
  if zr_special_p(m) || zr_type(m) != T_STRING
    m = zr_send(m, Machine.id(:to_s), 0, 0)
    return m if m == QUNDEF
  end
  if RString.len(m) == 0
    return zr_str_new(Machine.bytes("unhandled exception"), 19)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  p = RString.ptr(m)
  n = RString.len(m)
  first = 0
  while first < n && Machine.word(Machine.load8(p + first, 0)) != 10
    first += 1
  end
  zr_buf_push(b, p, first)
  zr_buf_push(b, Machine.bytes(" ("), 2)
  zr_buf_str(b, zr_class_name_of(recv))
  zr_buf_byte(b, 41)
  zr_buf_push(b, p + first, n - first)
  zr_buf_take(b)
end

# `#<Klass: to_s>`, or the class name alone when `to_s` is empty; a
# message with a newline is shown inspected.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_inspect(recv, argc, argv, cref, blk)
  m = zr_send(recv, Machine.id(:to_s), 0, 0)
  return m if m == QUNDEF
  if zr_special_p(m) || zr_type(m) != T_STRING
    m = zr_send(m, Machine.id(:to_s), 0, 0)
    return m if m == QUNDEF
  end
  if RString.len(m) == 0
    return zr_class_name_of(recv)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("#<"), 2)
  zr_buf_str(b, zr_class_name_of(recv))
  if zr_bytes_index(RString.ptr(m), RString.len(m), 10) >= 0
    zr_buf_byte(b, 58)
    zr_buf_str_escaped(b, RString.ptr(m), RString.len(m), !zr_str_wide_p(m))
  else
    zr_buf_push(b, Machine.bytes(": "), 2)
    zr_buf_str(b, m)
  end
  zr_buf_byte(b, 62)
  zr_buf_take(b)
end

# The byte `c` in `n` bytes at `p`: its index, or -1.
sig [Ptr, Word, Word] => Word
machine def zr_bytes_index(p, n, c)
  i = 0
  while i < n
    if Machine.word(Machine.load8(p + i, 0)) == c
      return i
    end
    i += 1
  end
  0 - 1
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_initialize(recv, argc, argv, cref, blk)
  if argc > 1
    return zr_wrong_arity_range(argc, 0, 1)
  end
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

# A FrameMeta placed where the frame `rec` stands now: the file and
# line an attribute is declared at.
sig [Ptr] => Ptr
machine def zr_meta_at(rec)
  from = Frame.meta(rec)
  meta = malloc(FrameMeta.size)
  FrameMeta.set_file(meta, FrameMeta.file(from))
  FrameMeta.set_file_len(meta, FrameMeta.file_len(from))
  FrameMeta.set_kind(meta, KIND_BUILTIN)
  FrameMeta.set_line(meta, Frame.line(rec))
  FrameMeta.set_parent(meta, 0)
  FrameMeta.set_arity(meta, 0)
  FrameMeta.set_params(meta, 0)
  FrameMeta.set_fn(meta, 0)
  meta
end

# `attr_reader`, `attr_writer`, `attr_accessor`: one entry per name,
# with the visibility the class body is at; the names defined answer.
sig [Value, Word, Ptr, Word] => Value
machine def zr_attr(klass, argc, argv, which)
  defined = zr_ary_new(argc * 2)
  i = 0
  while i < argc
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv + (i * 8), 0)), slot)
    return r if r == QUNDEF
    id = Machine.load64(slot, 0)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    unless zr_ident_p(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
      zr_buf_push(b, Machine.bytes("invalid attribute name '"), 24)
      zr_buf_sym(b, id)
      zr_buf_byte(b, 39)
      exc = zr_exc_new(zr_global(G_NAME_ERROR), zr_buf_take(b))
      zr_exc_detail(exc, Machine.id(:@name), zr_sym(id))
      zr_exc_detail(exc, Machine.id(:@receiver), klass)
      return zr_raise(exc)
    end
    zr_buf_byte(b, 64)
    zr_buf_sym(b, id)
    ivar = zr_intern(Buf.ptr(b), Buf.len(b))
    caller = Frame.prev(Task.top(zr_task()))
    # The scope's visibility verb applies only inside this class's own
    # body; from anywhere else the attribute is public.
    cref = Frame.cref(caller)
    if cref != QNIL && RCref.klass(zr_cref_lexical(cref)) != klass
      cref = Machine.value(QNIL)
    end
    if which != 2
      r = zr_define_method(klass, id, Machine.ptr(ivar), 0, KIND_ATTR_READER, zr_meta_at(caller), cref)
      if r == QUNDEF
        free(Buf.ptr(b))
        return r
      end
      zr_ary_push(defined, zr_sym(id))
    end
    if which != 1
      zr_buf_byte(b, 61)
      setter = zr_intern(Buf.ptr(b) + 1, Buf.len(b) - 1)
      r = zr_define_method(klass, setter, Machine.ptr(ivar), 1, KIND_ATTR_WRITER, zr_meta_at(caller), cref)
      if r == QUNDEF
        free(Buf.ptr(b))
        return r
      end
      zr_ary_push(defined, zr_sym(setter))
    end
    free(Buf.ptr(b))
    i += 1
  end
  defined
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

# `dig` continued into `v` with `rest`: CRuby's rb_obj_dig asks only
# an Array, Hash, Struct or an object with a public `dig`.
sig [Value, Value] => Value
machine def zr_dig_into(v, rest)
  klass = zr_class_of(v)
  e = zr_find_method(klass, Machine.id(:dig))
  if e == 0 || MEntry.vis(e) != VIS_PUBLIC
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_str(b, zr_class_name_of(v))
    zr_buf_push(b, Machine.bytes(" does not have #dig method"), 26)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  zr_send(v, Machine.id(:dig), RArray.len(rest), RArray.ptr(rest))
end

# CRuby's rb_equal: the same object is equal to itself and `==` is
# never asked. Every container reads its elements this way, which is
# what makes `[nan].include?(nan)` true while `nan == nan` is false.
sig [Value, Value] => Value
machine def zr_rb_equal(a, b)
  if a == b
    return Machine.value(QTRUE)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(b))
  r = zr_send(a, Machine.id(:==), 1, slot)
  return r if r == QUNDEF
  (r == QNIL || r == QFALSE) ? Machine.value(QFALSE) : Machine.value(QTRUE)
end
