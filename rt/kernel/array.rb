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

# `Array#initialize`: nothing, `(size, fill = nil)`, `(size) { |i| }`
# or `(array)`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_initialize(recv, argc, argv, cref, blk)
  if argc > 2
    return zr_wrong_arity_range(argc, 0, 2)
  end
  RArray.set_len(recv, 0)
  if argc == 0
    return recv
  end
  first = Machine.value(Machine.load64(argv, 0))
  if argc == 1 && !zr_special_p(first) && zr_type(first) == T_ARRAY
    i = 0
    while i < RArray.len(first)
      zr_ary_push(recv, zr_ary_at(first, i))
      i += 1
    end
    return recv
  end
  unless zr_fixnum_p(first)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    zr_buf_str(b, zr_class_name_of(first))
    zr_buf_push(b, Machine.bytes(" into Integer"), 13)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  n = zr_fix2long(first)
  if n < 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("negative array size"), 19)
  end
  fill = argc == 2 ? Machine.value(Machine.load64(argv, 8)) : Machine.value(QNIL)
  i = 0
  while i < n
    if blk != QNIL && argc == 1
      v = zr_yield1(blk, zr_fix(i))
      return v if v == QUNDEF
      zr_ary_push(recv, v)
    else
      zr_ary_push(recv, fill)
    end
    i += 1
  end
  recv
end

# The index of `v` in `a` by identity, or -1.
sig [Value, Value] => Word
machine def zr_ary_index_of(a, v)
  i = 0
  while i < RArray.len(a)
    if zr_ary_at(a, i) == v
      return i
    end
    i += 1
  end
  0 - 1
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

# `a[beg, len]`: a new Array of the elements from `beg`, or nil past
# the end; a start at the end answers an empty Array.
sig [Value, Word, Word] => Value
machine def zr_ary_subseq(a, beg, len)
  n = RArray.len(a)
  if beg > n || beg < 0 || len < 0
    return Machine.value(QNIL)
  end
  if n < beg + len
    len = n - beg
  end
  zr_ary_of(len, RArray.ptr(a) + (beg * 8))
end

# A Range as a start and a length against `n` elements, into `out`:
# false when the start is out of range.
sig [Value, Word, Ptr] => Value
machine def zr_range_beg_len(range, n, out)
  low = zr_ivar_get(range, Machine.id(:@begin))
  high = zr_ivar_get(range, Machine.id(:@end))
  slot = Machine.slot(8)
  if low == QNIL
    beg = 0
  else
    r = zr_index_operand(low, slot)
    return r if r == QUNDEF
    beg = Machine.load64(slot, 0)
  end
  if high == QNIL
    stop = n
  else
    r = zr_index_operand(high, slot)
    return r if r == QUNDEF
    stop = Machine.load64(slot, 0)
  end
  if beg < 0
    beg += n
    if beg < 0
      return Machine.value(QFALSE)
    end
  end
  if stop < 0
    stop += n
  end
  if high != QNIL && zr_ivar_get(range, Machine.id(:@excl)) != QTRUE
    stop += 1
  end
  len = stop - beg
  if len < 0
    len = 0
  end
  if beg > n
    return Machine.value(QFALSE)
  end
  Machine.store64(out, 0, beg)
  Machine.store64(out, 8, len)
  Machine.value(QTRUE)
end

# `a[i]`, `a[beg, len]` and `a[range]`.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_aref(recv, argc, argv, cref, blk)
  out = Machine.slot(16)
  first = Machine.value(Machine.load64(argv, 0))
  if argc == 2
    r = zr_index_operand(first, out)
    return r if r == QUNDEF
    r = zr_index_operand(Machine.value(Machine.load64(argv, 8)), out + 8)
    return r if r == QUNDEF
    beg = Machine.load64(out, 0)
    if beg < 0
      beg += RArray.len(recv)
    end
    return zr_ary_subseq(recv, beg, Machine.load64(out, 8))
  end
  if argc != 1
    return zr_wrong_arity_range(argc, 1, 2)
  end
  if !zr_special_p(first) && zr_class_of(first) == zr_global(G_RANGE)
    r = zr_range_beg_len(first, RArray.len(recv), out)
    return r if r == QUNDEF
    if r == QFALSE
      return Machine.value(QNIL)
    end
    return zr_ary_subseq(recv, Machine.load64(out, 0), Machine.load64(out, 8))
  end
  r = zr_index_operand(first, out)
  return r if r == QUNDEF
  zr_ary_at(recv, Machine.load64(out, 0))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_aset(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  out = Machine.slot(8)
  r = zr_index_operand(Machine.value(Machine.load64(argv, 0)), out)
  return r if r == QUNDEF
  zr_ary_store(recv, Machine.load64(out, 0), Machine.value(Machine.load64(argv, 8)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_push_m(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  i = 0
  while i < argc
    zr_ary_push(recv, Machine.value(Machine.load64(argv + (i * 8), 0)))
    i += 1
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_pop(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
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
  if RArray.len(recv) == 0
    return zr_str_new(Machine.bytes("[]"), 2)
  end
  if zr_guard_enter(recv, Machine.id(:inspect))
    return zr_str_new(Machine.bytes("[...]"), 5)
  end
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
      zr_guard_leave(recv, Machine.id(:inspect))
      return s
    end
    zr_buf_str(b, s)
    i += 1
  end
  zr_buf_byte(b, 93)
  zr_guard_leave(recv, Machine.id(:inspect))
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
  zr_call(recv, mid, argc, argv)
end

# `recv[i] = v` likewise, for an Integer index.
sig [Value, Word, Word, Ptr] => Value
machine def zr_opt_aset(recv, mid, argc, argv)
  if !zr_special_p(recv) && RBasic.klass(recv) == zr_global(G_ARRAY) && (Machine.load64(zr_gates(), 0) & GATE_ASET) == 0 && zr_fixnum_p(Machine.value(Machine.load64(argv, 0)))
    return zr_ary_aset(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
  end
  zr_call(recv, mid, argc, argv)
end

# The Array a multiple assignment takes apart: the value itself, its
# `to_ary` when it has one, else the value alone.
sig [Value] => Value
machine def zr_masgn_ary(v)
  if !zr_special_p(v) && zr_type(v) == T_ARRAY
    return v
  end
  if !zr_special_p(v) && zr_find_method(zr_class_of(v), Machine.id(:to_ary)) != 0
    a = zr_send(v, Machine.id(:to_ary), 0, 0)
    return a if a == QUNDEF
    if !zr_special_p(a) && zr_type(a) == T_ARRAY
      return a
    end
    if a != QNIL
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't convert to Array (to_ary gives something else)"), 52)
    end
  end
  a = zr_ary_new(1)
  zr_ary_push(a, v)
  a
end

# `a, *rest, b = ary`: the elements between the first `nlefts` and the
# last `nrights`, or none.
sig [Value, Word, Word] => Value
machine def zr_masgn_rest(ary, nlefts, nrights)
  from = nlefts
  to = RArray.len(ary) - nrights
  if to < from
    to = from
  end
  out = zr_ary_new(to - from)
  i = from
  while i < to
    zr_ary_push(out, zr_ary_at(ary, i))
    i += 1
  end
  out
end

# The `i`th of the `nrights` targets after a rest: from the end when
# the Array is long enough, else right after the `nlefts`.
sig [Value, Word, Word, Word] => Value
machine def zr_masgn_right(ary, nlefts, nrights, i)
  start = RArray.len(ary) - nrights
  if start < nlefts
    start = nlefts
  end
  zr_ary_at(ary, start + i)
end

# `a[beg, len] = vals`, the one edit every mutation is: the `len`
# elements from `beg` leave and `vals`'s elements take their place. A
# start past the end fills with nil first.
sig [Value, Value, Value, Value] => Value
machine def zr_ary_splice(a, beg_v, len_v, vals)
  if zr_frozen_p(a)
    return zr_frozen_error(a)
  end
  beg = zr_fix2long(beg_v)
  len = zr_fix2long(len_v)
  n = RArray.len(a)
  if beg < 0
    beg += n
    if beg < 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("index "), 6)
      zr_buf_long(b, beg - n)
      zr_buf_push(b, Machine.bytes(" too small for array; minimum: -"), 32)
      zr_buf_long(b, n)
      return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
    end
  end
  if len < 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("negative length ("), 17)
    zr_buf_long(b, len)
    zr_buf_byte(b, 41)
    return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
  end
  if beg > n
    zr_ary_store(a, beg - 1, Machine.value(QNIL))
    n = beg
  end
  if beg + len > n
    len = n - beg
  end
  m = RArray.len(vals)
  tail = n - beg - len
  zr_ary_reserve(a, n - len + m)
  p = RArray.ptr(a)
  if m != len
    zr_memmove(p + ((beg + m) * 8), p + ((beg + len) * 8), tail * 8)
  end
  zr_memcpy(p + (beg * 8), RArray.ptr(vals), m * 8)
  RArray.set_len(a, n - len + m)
  a
end

# Bytes moved between overlapping ranges, in whichever order keeps
# them intact.
sig [Ptr, Ptr, Word] => Void
machine def zr_memmove(to, from, n)
  if to < from
    zr_memcpy(to, from, n)
  else
    i = n
    while i > 0
      i -= 1
      Machine.store8(to + i, 0, Machine.load8(from + i, 0))
    end
  end
end

sig [Value, Value] => Value
machine def zr_ary_clear(a, unused)
  if zr_frozen_p(a)
    return zr_frozen_error(a)
  end
  RArray.set_len(a, 0)
  a
end
