# Strings: a length, a capacity and a buffer outside the arena.
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr

sig [Ptr, Word] => Value
machine def zr_str_new(bytes, len)
  s = zr_alloc(T_STRING, zr_global(G_STRING))
  buf = malloc(len + 1)
  zr_memcpy(buf, bytes, len)
  Machine.store8(buf + len, 0, Machine.i8(0))
  RString.set_ptr(s, buf)
  RString.set_len(s, len)
  RString.set_capa(s, len)
  s
end

# `String#initialize(str = "")`: the bytes copied in.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_initialize(recv, argc, argv, cref, blk)
  if argc > 1
    return zr_wrong_arity_range(argc, 0, 1)
  end
  if argc == 1
    src = Machine.value(Machine.load64(argv, 0))
    if zr_special_p(src) || zr_type(src) != T_STRING
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
      zr_buf_str(b, zr_class_name_of(src))
      zr_buf_push(b, Machine.bytes(" into String"), 12)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    buf = malloc(RString.len(src) + 1)
    zr_memcpy(buf, RString.ptr(src), RString.len(src))
    Machine.store8(buf + RString.len(src), 0, Machine.i8(0))
    free(RString.ptr(recv))
    RString.set_ptr(recv, buf)
    RString.set_len(recv, RString.len(src))
    RString.set_capa(recv, RString.len(src))
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_to_s(recv, argc, argv, cref, blk)
  recv
end

# Bytes are ASCII until encodings arrive: a method that would change a non-ASCII byte stops loudly instead of answering wrong.
G_FROZEN_ERROR = 27

sig [Value] => Bool
machine def zr_frozen_p(v)
  if zr_special_p(v)
    return true
  end
  (RBasic.flags(v) & FL_FREEZE) != 0
end

# `can't modify frozen String: "abc"`.
sig [Value] => Value
machine def zr_frozen_error(v)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("can't modify frozen "), 20)
  zr_buf_str(b, zr_class_name_of(v))
  zr_buf_push(b, Machine.bytes(": "), 2)
  s = zr_send(v, Machine.id(:inspect), 0, 0)
  if s == QUNDEF
    free(Buf.ptr(b))
    return s
  end
  zr_buf_str(b, s)
  zr_raise_buf(zr_global(G_FROZEN_ERROR), b)
end

# The String operand of a String method, else CRuby's TypeError.
sig [Value] => Value
machine def zr_str_operand(v)
  if zr_special_p(v) || zr_type(v) != T_STRING
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    if v == QNIL || v == QTRUE || v == QFALSE
      s = zr_send(v, Machine.id(:inspect), 0, 0)
      return s if s == QUNDEF
      zr_buf_str(b, s)
    else
      zr_buf_str(b, zr_class_name_of(v))
    end
    zr_buf_push(b, Machine.bytes(" into String"), 12)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  v
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_plus(recv, argc, argv, cref, blk)
  other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
  return other if other == QUNDEF
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_str(b, recv)
  zr_buf_str(b, other)
  zr_buf_take(b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_times(recv, argc, argv, cref, blk)
  out = Machine.slot(8)
  r = zr_index_operand(Machine.value(Machine.load64(argv, 0)), out)
  return r if r == QUNDEF
  n = Machine.load64(out, 0)
  if n < 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("negative argument"), 17)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  i = 0
  while i < n
    zr_buf_str(b, recv)
    i += 1
  end
  zr_buf_take(b)
end

# `<<` appends in place; a frozen receiver raises.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_concat(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
  return other if other == QUNDEF
  n = RString.len(recv) + RString.len(other)
  if n + 1 > RString.capa(recv)
    capa = RString.capa(recv) * 2
    if capa < n + 1
      capa = n + 1
    end
    p = malloc(capa)
    zr_memcpy(p, RString.ptr(recv), RString.len(recv))
    free(RString.ptr(recv))
    RString.set_ptr(recv, p)
    RString.set_capa(recv, capa)
  end
  zr_memcpy(RString.ptr(recv) + RString.len(recv), RString.ptr(other), RString.len(other))
  RString.set_len(recv, n)
  Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
  recv
end

# `String#<=>`: bytewise, nil against anything else.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_cmp(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_STRING
    return Machine.value(QNIL)
  end
  a = RString.ptr(recv)
  b = RString.ptr(other)
  n = RString.len(recv) < RString.len(other) ? RString.len(recv) : RString.len(other)
  i = 0
  while i < n
    x = Machine.word(Machine.load8(a + i, 0))
    y = Machine.word(Machine.load8(b + i, 0))
    if x != y
      return zr_fix(x < y ? 0 - 1 : 1)
    end
    i += 1
  end
  if RString.len(recv) == RString.len(other)
    return zr_fix(0)
  end
  zr_fix(RString.len(recv) < RString.len(other) ? 0 - 1 : 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_eq(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_STRING
    return Machine.value(QFALSE)
  end
  zr_bool(zr_bytes_eq(RString.ptr(recv), RString.len(recv), RString.ptr(other), RString.len(other)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_length(recv, argc, argv, cref, blk)
  zr_ascii_only(recv)
  zr_fix(RString.len(recv))
end

sig [Value] => Void
machine def zr_ascii_only(s)
  n = RString.len(s)
  i = 0
  while i < n
    if Machine.word(Machine.load8(RString.ptr(s) + i, 0)) >= 128
      zr_bug(Machine.bytes("a non-ASCII String is not supported yet\n"), 40)
    end
    i += 1
  end
end

# A copy with each byte mapped: 1 upcases, 2 downcases, 3 capitalizes.
sig [Value, Word] => Value
machine def zr_str_map_case(s, how)
  zr_ascii_only(s)
  n = RString.len(s)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  i = 0
  while i < n
    c = Machine.word(Machine.load8(RString.ptr(s) + i, 0))
    up = how == 1 || (how == 3 && i == 0)
    if up && c >= 97 && c <= 122
      c -= 32
    elsif !up && c >= 65 && c <= 90
      c += 32
    end
    zr_buf_byte(b, c)
    i += 1
  end
  zr_buf_take(b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_upcase(recv, argc, argv, cref, blk)
  zr_str_map_case(recv, 1)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_downcase(recv, argc, argv, cref, blk)
  zr_str_map_case(recv, 2)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_capitalize(recv, argc, argv, cref, blk)
  zr_str_map_case(recv, 3)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_reverse(recv, argc, argv, cref, blk)
  zr_ascii_only(recv)
  n = RString.len(recv)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  i = n - 1
  while i >= 0
    zr_buf_byte(b, Machine.word(Machine.load8(RString.ptr(recv) + i, 0)))
    i -= 1
  end
  zr_buf_take(b)
end

# The byte index of `needle` in `hay` from `from`, or -1.
sig [Value, Value, Word] => Word
machine def zr_str_find(hay, needle, from)
  n = RString.len(hay)
  m = RString.len(needle)
  i = from
  while i + m <= n
    if zr_bytes_eq(RString.ptr(hay) + i, m, RString.ptr(needle), m)
      return i
    end
    i += 1
  end
  0 - 1
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_include_p(recv, argc, argv, cref, blk)
  other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
  return other if other == QUNDEF
  zr_bool(zr_str_find(recv, other, 0) >= 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_index(recv, argc, argv, cref, blk)
  other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
  return other if other == QUNDEF
  zr_ascii_only(recv)
  i = zr_str_find(recv, other, 0)
  if i < 0
    return Machine.value(QNIL)
  end
  zr_fix(i)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_empty_p(recv, argc, argv, cref, blk)
  zr_bool(RString.len(recv) == 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_to_sym(recv, argc, argv, cref, blk)
  zr_sym(zr_intern(RString.ptr(recv), RString.len(recv)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_dup(recv, argc, argv, cref, blk)
  zr_str_new(RString.ptr(recv), RString.len(recv))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_freeze(recv, argc, argv, cref, blk)
  unless zr_special_p(recv)
    RBasic.set_flags(recv, RBasic.flags(recv) | FL_FREEZE)
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_frozen_p(recv, argc, argv, cref, blk)
  zr_bool(zr_frozen_p(recv))
end

# `succ`: the rightmost alphanumeric run counts up with carries, as
# CRuby does; a string with no alphanumerics bumps its last byte.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_succ(recv, argc, argv, cref, blk)
  zr_ascii_only(recv)
  n = RString.len(recv)
  if n == 0
    return zr_str_new(Machine.bytes(""), 0)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, RString.ptr(recv), n)
  p = Buf.ptr(b)
  i = n - 1
  alnum = false
  while i >= 0
    c = Machine.word(Machine.load8(p + i, 0))
    if zr_alnum_p(c)
      alnum = true
      break_here = false
      if c == 122
        Machine.store8(p + i, 0, Machine.i8(97))
      elsif c == 90
        Machine.store8(p + i, 0, Machine.i8(65))
      elsif c == 57
        Machine.store8(p + i, 0, Machine.i8(48))
      else
        Machine.store8(p + i, 0, Machine.i8(c + 1))
        break_here = true
      end
      if break_here
        return zr_buf_take(b)
      end
      # a carry past the leftmost alphanumeric inserts a new one
      j = i - 1
      while j >= 0 && !zr_alnum_p(Machine.word(Machine.load8(p + j, 0)))
        j -= 1
      end
      if j < 0
        first = c == 122 ? 97 : (c == 90 ? 65 : 49)
        zr_buf_byte(b, 0)
        p = Buf.ptr(b)
        k = Buf.len(b) - 1
        while k > i
          Machine.store8(p + k, 0, Machine.load8(p + k - 1, 0))
          k -= 1
        end
        Machine.store8(p + i, 0, Machine.i8(first))
        return zr_buf_take(b)
      end
      i = j
    else
      if alnum
        i -= 1
      else
        i -= 1
      end
    end
  end
  unless alnum
    Machine.store8(p + n - 1, 0, Machine.i8(Machine.word(Machine.load8(p + n - 1, 0)) + 1))
  end
  zr_buf_take(b)
end

sig [Word] => Bool
machine def zr_alnum_p(c)
  (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
end

# `"a#{b}c"`: each piece's `to_s`, joined; a `to_s` that answers no
# String falls back to the plain object form, as CRuby's does.
sig [Word, Ptr] => Value
machine def zr_str_interp(argc, argv)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  i = 0
  while i < argc
    v = Machine.value(Machine.load64(argv + (i * 8), 0))
    if !zr_special_p(v) && zr_type(v) == T_STRING
      zr_buf_str(b, v)
    else
      s = zr_send(v, Machine.id(:to_s), 0, 0)
      if s == QUNDEF
        free(Buf.ptr(b))
        return s
      end
      if !zr_special_p(s) && zr_type(s) == T_STRING
        zr_buf_str(b, s)
      else
        zr_buf_obj_head(b, v)
        zr_buf_byte(b, 62)
      end
    end
    i += 1
  end
  zr_buf_take(b)
end

# A frozen literal: the same String object at every evaluation.
sig [Ptr, Word] => Value
machine def zr_str_frozen(bytes, len)
  s = zr_str_new(bytes, len)
  RBasic.set_flags(s, RBasic.flags(s) | FL_FREEZE)
  s
end

GATE_LTLT = 16384

# `recv << v` as CRuby's opt_ltlt runs it: a String or Array whose `<<`
# is its own appends directly, with no frame.
sig [Value, Word, Word, Ptr] => Value
machine def zr_opt_ltlt(recv, mid, argc, argv)
  if !zr_special_p(recv) && (Machine.load64(zr_gates(), 0) & GATE_LTLT) == 0
    k = RBasic.klass(recv)
    other = Machine.value(Machine.load64(argv, 0))
    if k == zr_global(G_STRING) && !zr_special_p(other) && RBasic.klass(other) == zr_global(G_STRING)
      return zr_str_concat(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
    end
    if k == zr_global(G_ARRAY)
      return zr_ary_push_m(recv, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
    end
  end
  zr_call(recv, mid, argc, argv)
end
