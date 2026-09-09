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
  e = zr_exc_new(zr_global(G_FROZEN_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:@receiver), v)
  zr_raise(e)
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

sig [Value] => Bool
machine def zr_str_binary_p(s)
  (RBasic.flags(s) & FL_BINARY) != 0
end

sig [Value] => Value
machine def zr_str_set_binary(s)
  RBasic.set_flags(s, RBasic.flags(s) | FL_BINARY)
  s
end

# The encoding as a number: 0 UTF-8, 1 binary, 2 US-ASCII.
sig [Value] => Value
machine def zr_str_encoding_kind(s)
  if zr_str_binary_p(s)
    return zr_fix(1)
  end
  zr_fix((RBasic.flags(s) & FL_USASCII) != 0 ? 2 : 0)
end

sig [Value, Value] => Value
machine def zr_str_set_encoding(s, kind)
  flags = RBasic.flags(s) & (0 - (FL_BINARY + 1)) & (0 - (FL_USASCII + 1))
  k = zr_fix2long(kind)
  if k == 1
    flags = flags | FL_BINARY
  elsif k == 2
    flags = flags | FL_USASCII
  end
  RBasic.set_flags(s, flags)
  s
end

# Whether the join of two strings is binary: when both are, or when
# one is and the other holds only ASCII. A binary string of ASCII
# beside non-ASCII text joins as text; non-ASCII on both sides is
# CRuby's incompatibility error, not written yet.
sig [Value, Value] => Bool
machine def zr_str_join_binary_p(a, b)
  if zr_str_binary_p(a) == zr_str_binary_p(b)
    return zr_str_binary_p(a)
  end
  text = zr_str_binary_p(a) ? b : a
  if zr_str_bytes_are_chars(text)
    return true
  end
  binary = zr_str_binary_p(a) ? a : b
  if zr_str_ascii_bytes_p(binary)
    return false
  end
  zr_unimplemented(zr_str_new(Machine.bytes("joining a binary String with non-ASCII text"), 43))
  true
end

sig [Value] => Bool
machine def zr_str_ascii_bytes_p(s)
  n = RString.len(s)
  i = 0
  while i < n
    if Machine.word(Machine.load8(RString.ptr(s) + i, 0)) >= 128
      return false
    end
    i += 1
  end
  true
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_plus(recv, argc, argv, cref, blk)
  other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
  return other if other == QUNDEF
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_str(b, recv)
  zr_buf_str(b, other)
  s = zr_buf_take(b)
  if zr_str_join_binary_p(recv, other)
    zr_str_set_binary(s)
  elsif (RBasic.flags(recv) & FL_USASCII) != 0 && (RBasic.flags(other) & FL_USASCII) != 0
    RBasic.set_flags(s, RBasic.flags(s) | FL_USASCII)
  end
  s
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

# An Integer appended as a character: a byte of a binary string, a
# UTF-8 sequence of a text one.
sig [Value, Word] => Value
machine def zr_str_concat_codepoint(recv, c)
  limit = zr_str_binary_p(recv) ? 255 : 1114111
  if c < 0 || c > limit
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_long(b, c)
    zr_buf_push(b, Machine.bytes(" out of char range"), 18)
    return zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  if c < 128 || zr_str_binary_p(recv)
    zr_buf_byte(b, c)
  elsif c < 2048
    zr_buf_byte(b, 192 | (c >> 6))
    zr_buf_byte(b, 128 | (c & 63))
  elsif c < 65536
    zr_buf_byte(b, 224 | (c >> 12))
    zr_buf_byte(b, 128 | ((c >> 6) & 63))
    zr_buf_byte(b, 128 | (c & 63))
  else
    zr_buf_byte(b, 240 | (c >> 18))
    zr_buf_byte(b, 128 | ((c >> 12) & 63))
    zr_buf_byte(b, 128 | ((c >> 6) & 63))
    zr_buf_byte(b, 128 | (c & 63))
  end
  s = zr_buf_take(b)
  if zr_str_binary_p(recv)
    zr_str_set_binary(s)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(s))
  zr_str_concat(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
end

# `<<` appends in place; a frozen receiver raises.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_concat(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  if zr_fixnum_p(Machine.value(Machine.load64(argv, 0)))
    return zr_str_concat_codepoint(recv, zr_fix2long(Machine.value(Machine.load64(argv, 0))))
  end
  other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
  return other if other == QUNDEF
  binary = zr_str_join_binary_p(recv, other)
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
  if binary
    zr_str_set_binary(recv)
  elsif zr_str_binary_p(recv)
    RBasic.set_flags(recv, RBasic.flags(recv) & (0 - (FL_BINARY + 1)))
  elsif (RBasic.flags(recv) & FL_USASCII) != 0 && !zr_str_bytes_are_chars(other)
    RBasic.set_flags(recv, RBasic.flags(recv) & (0 - (FL_USASCII + 1)))
  end
  recv
end

# Two byte strings compared bytewise, the shorter first on a shared
# prefix: -1, 0 or 1.
sig [Ptr, Word, Ptr, Word] => Word
machine def zr_bytes_cmp(a, alen, b, blen)
  n = alen < blen ? alen : blen
  i = 0
  while i < n
    x = Machine.word(Machine.load8(a + i, 0))
    y = Machine.word(Machine.load8(b + i, 0))
    if x != y
      return x < y ? 0 - 1 : 1
    end
    i += 1
  end
  if alen == blen
    return 0
  end
  alen < blen ? 0 - 1 : 1
end

# `String#<=>`: bytewise, nil against anything else.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_cmp(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_STRING
    return Machine.value(QNIL)
  end
  zr_fix(zr_bytes_cmp(RString.ptr(recv), RString.len(recv), RString.ptr(other), RString.len(other)))
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
  zr_fix(zr_str_char_count(recv))
end

# Whether every byte is a character of its own: a binary string, or
# one with no byte past ASCII.
sig [Value] => Bool
machine def zr_str_bytes_are_chars(s)
  if zr_str_binary_p(s)
    return true
  end
  n = RString.len(s)
  i = 0
  while i < n
    if Machine.word(Machine.load8(RString.ptr(s) + i, 0)) >= 128
      return false
    end
    i += 1
  end
  true
end

sig [Value] => Value
machine def zr_str_ascii_check(s)
  zr_bool(zr_str_bytes_are_chars(s))
end

# The byte length of the character at byte `off`: a whole UTF-8
# sequence, else the one byte.
sig [Value, Word] => Word
machine def zr_str_char_len_at(s, off)
  if zr_str_binary_p(s)
    return 1
  end
  len = zr_utf8_char_len(RString.ptr(s) + off, RString.len(s) - off)
  len == 0 ? 1 : len
end

sig [Value] => Word
machine def zr_str_char_count(s)
  n = RString.len(s)
  count = 0
  i = 0
  while i < n
    i += zr_str_char_len_at(s, i)
    count += 1
  end
  count
end

# The byte offset of character `index` (negative counts from the
# end); the count itself maps to the end; past that, -1.
sig [Value, Word] => Word
machine def zr_str_char_offset(s, index)
  n = RString.len(s)
  if index < 0
    index += zr_str_char_count(s)
    if index < 0
      return 0 - 1
    end
  end
  i = 0
  while index > 0
    if i >= n
      return 0 - 1
    end
    i += zr_str_char_len_at(s, i)
    index -= 1
  end
  i
end

sig [Value, Value] => Value
machine def zr_str_char_offset_m(s, index)
  off = zr_str_char_offset(s, zr_fix2long(index))
  off < 0 ? Machine.value(QNIL) : zr_fix(off)
end

# The character index of byte `off`.
sig [Value, Value] => Value
machine def zr_str_byte_to_char(s, off)
  stop = zr_fix2long(off)
  i = 0
  count = 0
  while i < stop
    i += zr_str_char_len_at(s, i)
    count += 1
  end
  zr_fix(count)
end

# `len` characters from character `start`, or nil past the end.
sig [Value, Value, Value] => Value
machine def zr_str_char_slice(s, start, len)
  count = zr_fix2long(len)
  if count < 0
    return Machine.value(QNIL)
  end
  from = zr_str_char_offset(s, zr_fix2long(start))
  if from < 0
    return Machine.value(QNIL)
  end
  to = from
  n = RString.len(s)
  while count > 0 && to < n
    to += zr_str_char_len_at(s, to)
    count -= 1
  end
  zr_str_new(RString.ptr(s) + from, to - from)
end

sig [Value, Value] => Value
machine def zr_str_char_len_at_m(s, off)
  zr_fix(zr_str_char_len_at(s, zr_fix2long(off)))
end

# The code point of the first character.
sig [Value] => Value
machine def zr_str_ord(s)
  n = RString.len(s)
  if n == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("empty string"), 12)
  end
  p = RString.ptr(s)
  c = Machine.word(Machine.load8(p, 0))
  if zr_str_binary_p(s) || c < 128
    return zr_fix(c)
  end
  len = zr_utf8_char_len(p, n)
  if len == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("invalid byte sequence in UTF-8"), 30)
  end
  cp = c & ((1 << (7 - len)) - 1)
  i = 1
  while i < len
    cp = (cp << 6) | (Machine.word(Machine.load8(p + i, 0)) & 63)
    i += 1
  end
  zr_fix(cp)
end

sig [Value] => Value
machine def zr_str_valid_p(s)
  if zr_str_binary_p(s)
    return Machine.value(QTRUE)
  end
  n = RString.len(s)
  i = 0
  while i < n
    if Machine.word(Machine.load8(RString.ptr(s) + i, 0)) >= 128 && zr_utf8_char_len(RString.ptr(s) + i, n - i) == 0
      return Machine.value(QFALSE)
    end
    i += zr_str_char_len_at(s, i)
  end
  Machine.value(QTRUE)
end

sig [Value, Ptr, Word] => Void
machine def zr_non_ascii_stop(s, what, len)
  if !zr_str_bytes_are_chars(s)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("String#"), 7)
    zr_buf_push(b, what, len)
    zr_buf_push(b, Machine.bytes(" on a non-ASCII String"), 22)
    zr_unimplemented(zr_buf_take(b))
  end
end

# A copy with each byte mapped: 1 upcases, 2 downcases, 3 capitalizes.
sig [Value, Word] => Value
machine def zr_str_map_case(s, how)
  zr_non_ascii_stop(s, Machine.bytes("upcase, downcase or capitalize"), 30)
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
  n = RString.len(recv)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  end_ = n
  while end_ > 0
    start = end_ - 1
    while start > 0 && zr_str_char_len_at(recv, start) == 1 && (Machine.word(Machine.load8(RString.ptr(recv) + start, 0)) & 192) == 128
      start -= 1
    end
    zr_buf_push(b, RString.ptr(recv) + start, end_ - start)
    end_ = start
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
  i = zr_str_find(recv, other, 0)
  if i < 0
    return Machine.value(QNIL)
  end
  zr_str_byte_to_char(recv, zr_fix(i))
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

# `+str`: the string itself unless frozen, then a copy that is not.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_uplus(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return zr_str_new(RString.ptr(recv), RString.len(recv))
  end
  recv
end

# `-str`: the string itself when frozen, else a frozen copy.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_uminus(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    return recv
  end
  zr_str_frozen(RString.ptr(recv), RString.len(recv))
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
  zr_non_ascii_stop(recv, Machine.bytes("succ"), 4)
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

# The primitives rt/core/string.rb builds its methods on. Bytes are
# characters until encodings arrive: a method that would read a
# non-ASCII byte as a character stops loudly first.

sig [Value] => Value
machine def zr_str_bytesize(s)
  zr_fix(RString.len(s))
end

# The byte at `i`, or nil past the end.
sig [Value, Value] => Value
machine def zr_str_byte_at(s, i)
  n = zr_fix2long(i)
  if n < 0
    n += RString.len(s)
  end
  if n < 0 || n >= RString.len(s)
    return Machine.value(QNIL)
  end
  zr_fix(Machine.word(Machine.load8(RString.ptr(s) + n, 0)))
end

# A new String of `len` bytes from `off`, both already in range.
sig [Value, Value, Value] => Value
machine def zr_str_byteslice(s, off, len)
  out = zr_str_new(RString.ptr(s) + zr_fix2long(off), zr_fix2long(len))
  RBasic.set_flags(out, RBasic.flags(out) | (RBasic.flags(s) & (FL_BINARY | FL_USASCII)))
  out
end

# The receiver's bytes replaced by `other`'s.
sig [Value, Value] => Value
machine def zr_str_replace(s, other)
  if zr_frozen_p(s)
    return zr_frozen_error(s)
  end
  n = RString.len(other)
  buf = malloc(n + 1)
  zr_memcpy(buf, RString.ptr(other), n)
  Machine.store8(buf + n, 0, Machine.i8(0))
  free(RString.ptr(s))
  RString.set_ptr(s, buf)
  RString.set_len(s, n)
  RString.set_capa(s, n)
  s
end

# `setbyte`: the byte at `i` becomes `byte` modulo 256.
sig [Value, Value, Value] => Value
machine def zr_str_setbyte(s, i, byte)
  if zr_frozen_p(s)
    return zr_frozen_error(s)
  end
  n = zr_fix2long(i)
  if n < 0
    n += RString.len(s)
  end
  if n < 0 || n >= RString.len(s)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("index "), 6)
    zr_buf_long(b, zr_fix2long(i))
    zr_buf_push(b, Machine.bytes(" out of string"), 14)
    return zr_raise_buf(zr_global(G_INDEX_ERROR), b)
  end
  Machine.store8(RString.ptr(s) + n, 0, Machine.i8(zr_fix2long(byte) & 255))
  byte
end

# A String of one byte.
sig [Value] => Value
machine def zr_str_from_byte(byte)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_byte(b, zr_fix2long(byte) & 255)
  s = zr_buf_take(b)
  if zr_fix2long(byte) >= 128
    zr_str_set_binary(s)
  end
  s
end

# The byte index of `needle` at or after `start`, or nil.
sig [Value, Value, Value] => Value
machine def zr_str_find_from(s, needle, start)
  i = zr_str_find(s, needle, zr_fix2long(start))
  if i < 0
    return Machine.value(QNIL)
  end
  zr_fix(i)
end
