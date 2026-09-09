# Arrays: a length, a capacity and a buffer of Values outside the arena.
Machine.struct :RArray, basic: RBasic, len: Word, capa: Word, ptr: Ptr
G_ARRAY = 25
G_INDEX_ERROR = 26

sig [Word] => Value
machine def zr_ary_new(capa)
  a = zr_alloc(T_ARRAY, zr_global(G_ARRAY))
  if capa < 4
    capa = 4
  end
  RArray.set_ptr(a, malloc(capa * 8))
  RArray.set_len(a, 0)
  RArray.set_capa(a, capa)
  a
end

sig [Value] => Void
machine def zr_mark_ary(a)
  n = RArray.len(a)
  i = 0
  while i < n
    zr_mark(Machine.value(Machine.load64(RArray.ptr(a) + (i * 8), 0)))
    i += 1
  end
end

sig [Value, Word] => Value
machine def zr_ary_at(a, i)
  if i < 0
    i += RArray.len(a)
  end
  if i < 0 || i >= RArray.len(a)
    return Machine.value(QNIL)
  end
  Machine.value(Machine.load64(RArray.ptr(a) + (i * 8), 0))
end

sig [Value, Word] => Void
machine def zr_ary_reserve(a, n)
  if n > RArray.capa(a)
    capa = RArray.capa(a) * 2
    if capa < n
      capa = n
    end
    p = malloc(capa * 8)
    zr_memcpy(p, RArray.ptr(a), RArray.len(a) * 8)
    free(RArray.ptr(a))
    RArray.set_ptr(a, p)
    RArray.set_capa(a, capa)
  end
end

sig [Value, Value] => Void
machine def zr_ary_push(a, v)
  n = RArray.len(a)
  zr_ary_reserve(a, n + 1)
  Machine.store64(RArray.ptr(a) + (n * 8), 0, Machine.word(v))
  RArray.set_len(a, n + 1)
end

# `a[i] = v`, filling with nil past the end.
sig [Value, Word, Value] => Value
machine def zr_ary_store(a, i, v)
  n = RArray.len(a)
  if i < 0
    i += n
    if i < 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("index "), 6)
      zr_buf_long(b, i - n)
      zr_buf_push(b, Machine.bytes(" too small for array; minimum: -"), 32)
      zr_buf_long(b, n)
      return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
    end
  end
  if i >= n
    zr_ary_reserve(a, i + 1)
    j = n
    while j < i
      Machine.store64(RArray.ptr(a) + (j * 8), 0, QNIL)
      j += 1
    end
    RArray.set_len(a, i + 1)
  end
  Machine.store64(RArray.ptr(a) + (i * 8), 0, Machine.word(v))
  v
end

# An Array of the `argc` Values at `argv`.
sig [Word, Ptr] => Value
machine def zr_ary_of(argc, argv)
  a = zr_ary_new(argc)
  zr_memcpy(RArray.ptr(a), argv, argc * 8)
  RArray.set_len(a, argc)
  a
end

# `*value` in an argument list or an Array literal: an Array's elements,
# nothing for nil, else `to_a`'s elements, or the value itself when it
# has no `to_a`.
sig [Value, Value] => Value
machine def zr_ary_splat(a, v)
  if v == QNIL
    return a
  end
  if zr_special_p(v) || zr_type(v) != T_ARRAY
    if zr_find_method(zr_class_of(v), Machine.id(:to_a)) == 0
      zr_ary_push(a, v)
      return a
    end
    v = zr_send(v, Machine.id(:to_a), 0, 0)
    return v if v == QUNDEF
    if zr_special_p(v) || zr_type(v) != T_ARRAY
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't convert to Array (to_a gives something else)"), 50)
    end
  end
  i = 0
  while i < RArray.len(v)
    zr_ary_push(a, zr_ary_at(v, i))
    i += 1
  end
  a
end

sig [Value, Ptr] => Value
machine def zr_index_operand(v, out)
  unless zr_fixnum_p(v)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    zr_buf_str(b, zr_class_name_of(v))
    zr_buf_push(b, Machine.bytes(" into Integer"), 13)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  Machine.store64(out, 0, zr_fix2long(v))
  Machine.value(QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_aref(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_index_operand(Machine.value(Machine.load64(argv, 0)), out)
  return r if r == QUNDEF
  zr_ary_at(recv, Machine.load64(out, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_aset(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_index_operand(Machine.value(Machine.load64(argv, 0)), out)
  return r if r == QUNDEF
  zr_ary_store(recv, Machine.load64(out, 0), Machine.value(Machine.load64(argv, 8)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_push_m(recv, argc, argv, cref, blk)
  i = 0
  while i < argc
    zr_ary_push(recv, Machine.value(Machine.load64(argv + (i * 8), 0)))
    i += 1
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_pop(recv, argc, argv, cref, blk)
  n = RArray.len(recv)
  if n == 0
    return Machine.value(QNIL)
  end
  RArray.set_len(recv, n - 1)
  Machine.value(Machine.load64(RArray.ptr(recv) + ((n - 1) * 8), 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_length(recv, argc, argv, cref, blk)
  zr_fix(RArray.len(recv))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_empty_p(recv, argc, argv, cref, blk)
  zr_bool(RArray.len(recv) == 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_first(recv, argc, argv, cref, blk)
  zr_ary_at(recv, 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_last(recv, argc, argv, cref, blk)
  zr_ary_at(recv, 0 - 1)
end

# `[1, 2]`: each element's inspect may run Ruby, so the buffer is
# re-read by index.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_inspect(recv, argc, argv, cref, blk)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_byte(b, 91)
  i = 0
  while i < RArray.len(recv)
    if i > 0
      zr_buf_push(b, Machine.bytes(", "), 2)
    end
    s = zr_send(zr_ary_at(recv, i), Machine.id(:inspect), 0, 0)
    if s == QUNDEF
      free(Buf.ptr(b))
      return s
    end
    zr_buf_str(b, s)
    i += 1
  end
  zr_buf_byte(b, 93)
  zr_buf_take(b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_eq(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_ARRAY
    return Machine.value(QFALSE)
  end
  if RArray.len(recv) != RArray.len(other)
    return Machine.value(QFALSE)
  end
  i = 0
  while i < RArray.len(recv)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_ary_at(other, i)))
    r = zr_send(zr_ary_at(recv, i), Machine.id(:==), 1, slot)
    return r if r == QUNDEF
    if r == QNIL || r == QFALSE
      return Machine.value(QFALSE)
    end
    i += 1
  end
  Machine.value(QTRUE)
end

# `recv[i]` as CRuby's opt_aref instruction runs it: an Array whose `[]`
# is its own is read directly, with no frame for a backtrace.
sig [Value, Word, Word, Ptr] => Value
machine def zr_opt_aref(recv, mid, argc, argv)
  if !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_ARRAY) && (Machine.load64(zr_gates(), 0) & GATE_AREF) == 0
    return zr_ary_aref(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
  end
  zr_send(recv, mid, argc, argv)
end

# `recv[i] = v` likewise, for an Integer index.
sig [Value, Word, Word, Ptr] => Value
machine def zr_opt_aset(recv, mid, argc, argv)
  if !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_ARRAY) && (Machine.load64(zr_gates(), 0) & GATE_ASET) == 0 && zr_fixnum_p(Machine.value(Machine.load64(argv, 0)))
    return zr_ary_aset(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
  end
  zr_send(recv, mid, argc, argv)
end
