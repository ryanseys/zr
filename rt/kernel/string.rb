# Strings: a length, a capacity and a buffer outside the arena.
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr

# A String whose bytes a scan found all below 0x80, which CRuby calls
# the 7-bit coderange. Every write to the bytes clears it, so a String
# read many times is scanned once.
FL_ASCII = 1 << 21
FL_ASCII_CLEAR = 0 - FL_ASCII - 1

# The bytes of `s` changed: what a scan found about them is gone.
sig [Value] => Void
machine def zr_str_modified(s)
  RBasic.set_flags(s, RBasic.flags(s) & FL_ASCII_CLEAR)
end

sig [Ptr, Word] => Value
machine def zr_str_new(bytes, len)
  s = zr_alloc(T_STRING, zr_global(G_STRING))
  buf = zr_xmalloc(len + 1)
  zr_memcpy(buf, bytes, len)
  Machine.store8(buf + len, 0, Machine.i8(0))
  RString.set_ptr(s, buf)
  RString.set_len(s, len)
  RString.set_capa(s, len)
  s
end

# `String#initialize(source)`: the source's bytes and encoding copied
# in; a nil source leaves the receiver empty.
sig [Value, Value] => Value
machine def zr_str_initialize_m(recv, src)
  if src == QNIL
    return recv
  end
  if zr_special_p(src) || zr_type(src) != T_STRING
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    zr_buf_class_of(b, src)
    zr_buf_push(b, Machine.bytes(" into String"), 12)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  buf = zr_xmalloc(RString.len(src) + 1)
  zr_memcpy(buf, RString.ptr(src), RString.len(src))
  Machine.store8(buf + RString.len(src), 0, Machine.i8(0))
  free(RString.ptr(recv))
  RString.set_ptr(recv, buf)
  RString.set_len(recv, RString.len(src))
  RString.set_capa(recv, RString.len(src))
  zr_str_modified(recv)
  zr_str_copy_encoding(recv, src)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_initialize(recv, argc, argv, cref, blk)
  if argc > 1
    return zr_wrong_arity_range(argc, 0, 1)
  end
  zr_str_initialize_m(recv, argc == 1 ? Machine.value(Machine.load64(argv, 0)) : Machine.value(QNIL))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_to_s(recv, argc, argv, cref, blk)
  if zr_real_class(recv) != zr_global(G_STRING)
    return zr_str_new(RString.ptr(recv), RString.len(recv))
  end
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
  zr_buf_class_of(b, v)
  zr_buf_push(b, Machine.bytes(": "), 2)
  s = zr_inspect(v)
  if s == QUNDEF
    free(Buf.ptr(b))
    return s
  end
  zr_buf_str(b, s)
  e = zr_exc_new(zr_global(G_FROZEN_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:@receiver), v)
  zr_raise(e)
end

# The String operand of a String method: a String, or what `to_str`
# answers, else CRuby's TypeError.
sig [Value] => Value
machine def zr_str_operand(v)
  if zr_special_p(v) || zr_type(v) != T_STRING
    if !zr_special_p(v) && zr_find_method(zr_class_of(v), Machine.id(:to_str)) != 0
      s = zr_send(v, Machine.id(:to_str), 0, 0)
      return s if s == QUNDEF
      if !zr_special_p(s) && zr_type(s) == T_STRING
        return s
      end
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("can't convert "), 14)
      zr_buf_class_of(b, v)
      zr_buf_push(b, Machine.bytes(" to String ("), 12)
      zr_buf_class_of(b, v)
      zr_buf_push(b, Machine.bytes("#to_str gives "), 14)
      zr_buf_class_of(b, s)
      zr_buf_push(b, Machine.bytes(")"), 1)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    if v == QNIL || v == QTRUE || v == QFALSE
      s = zr_inspect(v)
      return s if s == QUNDEF
      zr_buf_str(b, s)
    else
      zr_buf_class_of(b, v)
    end
    zr_buf_push(b, Machine.bytes(" into String"), 12)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  v
end

# The encoding `s` carries: ruby's own index into `Encoding.list`.
sig [Value] => Word
machine def zr_str_encoding_index(s)
  i = (RBasic.flags(s) >> FL_ENC_SHIFT) & 255
  i < 2 ? 1 - i : i
end

sig [Value, Word] => Value
machine def zr_str_set_index(s, index)
  i = index < 2 ? 1 - index : index
  RBasic.set_flags(s, (RBasic.flags(s) & FL_ENC_KEEP) | (i << FL_ENC_SHIFT))
  s
end

# The encoding `src` carries, onto `s`.
sig [Value, Value] => Value
machine def zr_str_copy_encoding(s, src)
  zr_str_set_index(s, zr_str_encoding_index(src))
end

sig [Value] => Bool
machine def zr_str_binary_p(s)
  zr_str_encoding_index(s) == ENC_BINARY
end

# Whether one character can span bytes. Of the encodings a String
# carries, UTF-8 alone does; every other one this runtime accepts
# gives each byte a character of its own.
sig [Value] => Bool
machine def zr_str_wide_p(s)
  zr_str_encoding_index(s) == ENC_UTF8
end

sig [Value] => Value
machine def zr_str_set_binary(s)
  zr_str_set_index(s, ENC_BINARY)
end

sig [Value] => Value
machine def zr_str_encoding_index_m(s)
  zr_fix(zr_str_encoding_index(s))
end

sig [Value, Value] => Value
machine def zr_str_set_index_m(s, index)
  zr_str_set_index(s, zr_fix2long(index))
end

# The encoding a join takes: the side that is not plain ASCII, which
# is ruby's own compatibility rule. Both sides plain ASCII gives the
# receiver's, so `"a" + "b".b` stays text.
sig [Value, Value] => Word
machine def zr_str_join_index(a, b)
  zr_str_ascii_bytes_p(b) ? zr_str_encoding_index(a) : zr_str_encoding_index(b)
end

# Whether joining `a` and `b` is ruby's compatibility error: two
# encodings, with a byte past ASCII on each side.
sig [Value, Value] => Bool
machine def zr_str_join_incompatible_p(a, b)
  zr_str_encoding_index(a) != zr_str_encoding_index(b) && !zr_str_ascii_bytes_p(a) && !zr_str_ascii_bytes_p(b)
end

# The error, the receiver's encoding named first. Encoding holds the
# names, so it writes the message.
sig [Value, Value] => Value
machine def zr_str_join_incompatible(a, b)
  klass = zr_core_class(Machine.id(:Encoding))
  slot = Machine.slot(16)
  Machine.store64(slot, 0, Machine.word(a))
  Machine.store64(slot, 8, Machine.word(b))
  zr_send(klass, Machine.id(:incompatible), 2, slot)
end

sig [Value] => Bool
machine def zr_str_ascii_bytes_p(s)
  if (RBasic.flags(s) & FL_ASCII) != 0
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
  RBasic.set_flags(s, RBasic.flags(s) | FL_ASCII)
  true
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_plus(recv, argc, argv, cref, blk)
  other = zr_str_operand(Machine.value(Machine.load64(argv, 0)))
  return other if other == QUNDEF
  if zr_str_join_incompatible_p(recv, other)
    return zr_str_join_incompatible(recv, other)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_str(b, recv)
  zr_buf_str(b, other)
  s = zr_buf_take(b)
  # The join takes the encoding of whichever side is not plain ASCII,
  # which is ruby's own compatibility rule.
  zr_str_set_index(s, zr_str_ascii_only(other) ? zr_str_encoding_index(recv) : zr_str_encoding_index(other))
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
  # The size the copies would take, checked before any of them is made.
  if n != 0 && (9223372036854775807 / n) < RString.len(recv)
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("argument too big"), 16)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  i = 0
  while i < n
    zr_buf_str(b, recv)
    i += 1
  end
  zr_str_copy_encoding(zr_buf_take(b), recv)
end

# An Integer appended as a character: a byte of a binary string, a
# UTF-8 sequence of a text one.
sig [Value, Word] => Value
machine def zr_str_concat_codepoint(recv, c)
  limit = zr_str_wide_p(recv) ? 1114111 : 255
  if zr_str_wide_p(recv) && c >= 55296 && c <= 57343
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("invalid codepoint 0x"), 20)
    shift = 12
    while shift >= 0
      digit = (c >> shift) & 15
      zr_buf_byte(b, digit < 10 ? 48 + digit : 55 + digit)
      shift -= 4
    end
    zr_buf_push(b, Machine.bytes(" in UTF-8"), 9)
    return zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b)
  end
  if c < 0 || c > limit
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_long(b, c)
    zr_buf_push(b, Machine.bytes(" out of char range"), 18)
    return zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b)
  end
  # A byte past ASCII makes a US-ASCII String binary, as rb_str_concat
  # has it; a frozen one raises before its encoding changes.
  if c > 127 && zr_str_encoding_index(recv) == ENC_USASCII
    if zr_frozen_p(recv)
      return zr_frozen_error(recv)
    end
    zr_str_set_binary(recv)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  if c < 128 || !zr_str_wide_p(recv)
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
  s = zr_str_copy_encoding(zr_buf_take(b), recv)
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
  if zr_str_join_incompatible_p(recv, other)
    return zr_str_join_incompatible(recv, other)
  end
  index = zr_str_join_index(recv, other)
  # Plain ASCII onto plain ASCII stays plain ASCII.
  ascii = (RBasic.flags(recv) & RBasic.flags(other) & FL_ASCII) != 0
  n = RString.len(recv) + RString.len(other)
  if n + 1 > RString.capa(recv)
    capa = RString.capa(recv) * 2
    if capa < n + 1
      capa = n + 1
    end
    p = zr_xmalloc(capa)
    zr_memcpy(p, RString.ptr(recv), RString.len(recv))
    free(RString.ptr(recv))
    RString.set_ptr(recv, p)
    RString.set_capa(recv, capa)
  end
  zr_memcpy(RString.ptr(recv) + RString.len(recv), RString.ptr(other), RString.len(other))
  RString.set_len(recv, n)
  Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
  if !ascii
    zr_str_modified(recv)
  end
  zr_str_set_index(recv, index)
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
  r = zr_bytes_cmp(RString.ptr(recv), RString.len(recv), RString.ptr(other), RString.len(other))
  if r != 0 || zr_str_comparable(recv, other)
    return zr_fix(r)
  end
  a = zr_str_encoding_index(recv)
  b = zr_str_encoding_index(other)
  zr_fix(a < b ? 0 - 1 : 1)
end

# Two strings compare only when they hold one encoding, or when both
# are ASCII throughout.
sig [Value, Value] => Bool
machine def zr_str_comparable(a, b)
  zr_str_encoding_index(a) == zr_str_encoding_index(b) || (zr_str_ascii_only(a) && zr_str_ascii_only(b))
end

sig [Value] => Bool
machine def zr_str_ascii_only(s)
  i = 0
  while i < RString.len(s)
    if Machine.word(Machine.load8(RString.ptr(s) + i, 0)) >= 128
      return false
    end
    i += 1
  end
  true
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_eq(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_STRING
    return Machine.value(QFALSE)
  end
  zr_bool(zr_bytes_eq(RString.ptr(recv), RString.len(recv), RString.ptr(other), RString.len(other)) && zr_str_comparable(recv, other))
end

# `String#==`: another String by its bytes; anything else that answers
# to_str is asked `other == self`, as CRuby's rb_str_equal does.
# `eql?` keeps the plain rule of zr_str_eq.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_equal(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if !zr_special_p(other) && zr_type(other) == T_STRING
    return zr_str_eq(recv, argc, argv, cref, blk)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(zr_sym(Machine.id(:to_str))))
  responds = zr_send(other, Machine.id(:respond_to?), 1, slot)
  return responds if responds == QUNDEF
  if responds == QNIL || responds == QFALSE
    return Machine.value(QFALSE)
  end
  Machine.store64(slot, 0, Machine.word(recv))
  r = zr_send(other, Machine.id(:==), 1, slot)
  return r if r == QUNDEF
  zr_bool(r != QNIL && r != QFALSE)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_length(recv, argc, argv, cref, blk)
  zr_fix(zr_str_char_count(recv))
end

# Whether every byte is a character of its own: a byte-oriented
# encoding, or text with no byte past ASCII.
sig [Value] => Bool
machine def zr_str_bytes_are_chars(s)
  if !zr_str_wide_p(s)
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
  # The flag alone, never a scan: this runs once for each character.
  if (RBasic.flags(s) & FL_ASCII) != 0 || !zr_str_wide_p(s)
    return 1
  end
  len = zr_utf8_char_len(RString.ptr(s) + off, RString.len(s) - off)
  len == 0 ? 1 : len
end

sig [Value] => Word
machine def zr_str_char_count(s)
  n = RString.len(s)
  if !zr_str_wide_p(s) || zr_str_ascii_bytes_p(s)
    return n
  end
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
  # One byte a character: the index is the offset.
  if !zr_str_wide_p(s) || zr_str_ascii_bytes_p(s)
    if index < 0
      index += n
    end
    if index < 0 || index > n
      return 0 - 1
    end
    return index
  end
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
  zr_str_copy_encoding(zr_str_new(RString.ptr(s) + from, to - from), s)
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
  if c < 128 || !zr_str_wide_p(s)
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

# US-ASCII stops at 128, UTF-8 needs whole sequences, and every other
# encoding this runtime carries takes any byte.
sig [Value] => Value
machine def zr_str_valid_p(s)
  if zr_str_encoding_index(s) == ENC_USASCII
    return zr_bool(zr_str_ascii_bytes_p(s))
  end
  if !zr_str_wide_p(s)
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

# A stop on a String whose bytes are not all characters; nil when
# they are.
sig [Value, Ptr, Word] => Value
machine def zr_non_ascii_stop(s, what, len)
  if zr_str_bytes_are_chars(s)
    return Machine.value(QNIL)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("String#"), 7)
  zr_buf_push(b, what, len)
  zr_buf_push(b, Machine.bytes(" on a non-ASCII String"), 22)
  zr_unimplemented(zr_buf_take(b))
end

# A copy with each byte mapped: 1 upcases, 2 downcases, 3 capitalizes.
sig [Value, Word] => Value
machine def zr_str_map_case(s, how)
  r = zr_non_ascii_stop(s, Machine.bytes("upcase, downcase or capitalize"), 30)
  return r if r == QUNDEF
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
  zr_str_copy_encoding(zr_buf_take(b), s)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_upcase(recv, argc, argv, cref, blk)
  zr_str_map_case(recv, 1)
end

# The core's own case mapping, past any String method a program adds.
sig [Value, Value] => Value
machine def zr_str_map_case_m(s, how)
  zr_str_map_case(s, zr_fix2long(how))
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
  # The characters are found from the front, where they start, and each
  # goes to its place from the back; an invalid byte is one character.
  n = RString.len(recv)
  out = zr_str_new(RString.ptr(recv), n)
  i = 0
  while i < n
    len = zr_str_char_len_at(recv, i)
    zr_memmove(RString.ptr(out) + n - i - len, RString.ptr(recv) + i, len)
    i += len
  end
  zr_str_copy_encoding(out, recv)
end

# The byte index of `needle` in `hay` from `from`, or -1. A needle that
# is not valid in its encoding never matches, as rb_str_index decides.
sig [Value, Value, Word] => Word
machine def zr_str_find(hay, needle, from)
  if zr_str_valid_p(needle) == QFALSE
    return 0 - 1
  end
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

# `+str`: the string itself unless frozen, then a copy that is not,
# with its encoding and class, as rb_str_dup makes it.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_uplus(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv)
    copy = zr_str_copy_encoding(zr_str_new(RString.ptr(recv), RString.len(recv)), recv)
    RBasic.set_klass(copy, zr_real_class(recv))
    return copy
  end
  recv
end

# `-str`, as CRuby's str_uminus decides. A bare String (class String,
# no ivars) is interned: when frozen as it is, else as a copy of its
# bytes and encoding. Any other String is not interned: a frozen one
# answers itself, and an unfrozen one a frozen copy of its class.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_uminus(recv, argc, argv, cref, blk)
  bare = RBasic.klass(recv) == zr_global(G_STRING) && (RBasic.flags(recv) & FL_EXIVAR) == 0
  if zr_frozen_p(recv)
    return bare ? zr_str_intern(recv) : recv
  end
  copy = zr_str_copy_encoding(zr_str_new(RString.ptr(recv), RString.len(recv)), recv)
  if zr_real_class(recv) != zr_global(G_STRING)
    RBasic.set_klass(copy, zr_real_class(recv))
    RBasic.set_flags(copy, RBasic.flags(copy) | FL_FREEZE)
    return copy
  end
  zr_str_intern(copy)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_freeze(recv, argc, argv, cref, blk)
  unless zr_special_p(recv)
    RBasic.set_flags(recv, RBasic.flags(recv) | FL_FREEZE)
    # The singleton class freezes with its object, as CRuby's
    # rb_freeze_singleton_class does.
    k = RBasic.klass(recv)
    if zr_singleton_p(k) && RClass.attached(k) == recv
      RBasic.set_flags(k, RBasic.flags(k) | FL_FREEZE)
    end
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_frozen_p(recv, argc, argv, cref, blk)
  zr_bool(zr_frozen_p(recv))
end

# `succ` of an ASCII string: the rightmost alphanumeric run counts up
# with carries, as CRuby does; a string with no alphanumerics bumps
# its last byte. The core handles other strings.
sig [Value] => Value
machine def zr_str_succ_ascii(recv)
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
      # a carry past the leftmost alphanumeric inserts a new one; so
      # does one that would cross a gap into the other kind (a letter
      # after a digit, or a digit after a letter)
      j = i - 1
      while j >= 0 && !zr_alnum_p(Machine.word(Machine.load8(p + j, 0)))
        j -= 1
      end
      if j >= 0 && j < i - 1 && (c <= 57) != (Machine.word(Machine.load8(p + j, 0)) <= 57)
        j = 0 - 1
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
# String falls back to the plain object form, as CRuby's does. The
# result takes the encoding of the first piece that is not plain
# ASCII, and a second such piece in another encoding is an error.
sig [Word, Ptr] => Value
machine def zr_str_interp(argc, argv)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  index = ENC_UTF8
  ascii = true
  i = 0
  while i < argc
    v = Machine.value(Machine.load64(argv + (i * 8), 0))
    s = v
    if zr_special_p(v) || zr_type(v) != T_STRING
      s = zr_obj_as_string(v)
      if s == QUNDEF
        free(Buf.ptr(b))
        return s
      end
    end
    if zr_special_p(s) || zr_type(s) != T_STRING
      zr_buf_obj_head(b, v)
      zr_buf_byte(b, 62)
    elsif zr_str_ascii_bytes_p(s)
      zr_buf_str(b, s)
    elsif ascii
      index = zr_str_encoding_index(s)
      ascii = false
      zr_buf_str(b, s)
    elsif index != zr_str_encoding_index(s)
      return zr_str_join_incompatible(zr_str_set_index(zr_buf_take(b), index), s)
    else
      zr_buf_str(b, s)
    end
    i += 1
  end
  zr_str_set_index(zr_buf_take(b), index)
end

# A frozen literal: the same String object at every evaluation.
sig [Ptr, Word] => Value
machine def zr_str_frozen(bytes, len)
  zr_str_intern(zr_str_new(bytes, len))
end

# The same three, for a file whose script encoding is not UTF-8: the
# literal takes the encoding before anything reads its bytes.
sig [Ptr, Word, Word] => Value
machine def zr_str_new_at(bytes, len, index)
  zr_str_set_index(zr_str_new(bytes, len), index)
end

sig [Ptr, Word, Word] => Value
machine def zr_str_frozen_at(bytes, len, index)
  zr_str_intern(zr_str_new_at(bytes, len, index))
end

sig [Ptr, Word, Word] => Value
machine def zr_str_literal_freeze_at(bytes, len, index)
  if (Machine.load64(zr_gates(), 0) & GATE_FREEZE) != 0
    return zr_send(zr_str_new_at(bytes, len, index), Machine.id(:freeze), 0, 0)
  end
  zr_str_frozen_at(bytes, len, index)
end

# `"lit".freeze`: the shared frozen String, unless the program has
# redefined String#freeze, which then runs as any send.
sig [Ptr, Word] => Value
machine def zr_str_literal_freeze(bytes, len)
  if (Machine.load64(zr_gates(), 0) & GATE_FREEZE) != 0
    return zr_send(zr_str_new(bytes, len), Machine.id(:freeze), 0, 0)
  end
  zr_str_frozen(bytes, len)
end

GATE_FREEZE = 32768

G_FSTRINGS = 44

# CRuby's fstring table: the one frozen String of these bytes. A
# String not yet in the table is frozen and kept; one outside UTF-8 is
# frozen but not shared, since the table keys on bytes alone.
sig [Value] => Value
machine def zr_str_intern(s)
  if !zr_str_wide_p(s)
    RBasic.set_flags(s, RBasic.flags(s) | FL_FREEZE)
    return s
  end
  table = zr_global(G_FSTRINGS)
  if zr_special_p(table)
    table = zr_hash_new()
    zr_set_global(G_FSTRINGS, table)
  end
  found = zr_hash_lookup(table, s)
  if found != QUNDEF
    return found
  end
  RBasic.set_flags(s, RBasic.flags(s) | FL_FREEZE | FL_FSTR)
  zr_hash_store(table, s, s)
  s
end

# A String the fstring table holds, which can have no singleton class
# (CRuby's RSTRING_FSTR).
FL_FSTR = 1 << 22

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
  zr_str_copy_encoding(zr_str_new(RString.ptr(s) + zr_fix2long(off), zr_fix2long(len)), s)
end

# The receiver's bytes replaced by `other`'s.
sig [Value, Value] => Value
machine def zr_str_replace(s, other)
  if zr_frozen_p(s)
    return zr_frozen_error(s)
  end
  n = RString.len(other)
  buf = zr_xmalloc(n + 1)
  zr_memcpy(buf, RString.ptr(other), n)
  Machine.store8(buf + n, 0, Machine.i8(0))
  free(RString.ptr(s))
  RString.set_ptr(s, buf)
  RString.set_len(s, n)
  RString.set_capa(s, n)
  zr_str_modified(s)
  zr_str_copy_encoding(s, other)
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
  zr_str_modified(s)
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

# The first `n` bytes of `s` as a new String, and `s` keeps the rest at
# its front: a read buffer hands out a line without copying what is
# left into a String of its own. Fewer bytes stay plain ASCII if all
# of them were, so FL_ASCII holds.
sig [Value, Value] => Value
machine def zr_str_shift_front(s, n)
  len = RString.len(s)
  k = zr_fix2long(n)
  if k > len
    k = len
  end
  out = zr_str_copy_encoding(zr_str_new(RString.ptr(s), k), s)
  zr_memmove(RString.ptr(s), RString.ptr(s) + k, len - k)
  RString.set_len(s, len - k)
  Machine.store8(RString.ptr(s) + len - k, 0, Machine.i8(0))
  out
end

# Whitespace to strip and split: space and \t through \r, and NUL too
# when `nul` is true, as strip has it and split does not.
sig [Word, Value] => Bool
machine def zr_space_byte_p(c, nul)
  c == 32 || (c >= 9 && c <= 13) || (c == 0 && nul == QTRUE)
end

# The first offset at or after `from` whose byte is not whitespace, or
# the length.
sig [Value, Value, Value] => Value
machine def zr_str_space_end(s, from, nul)
  n = RString.len(s)
  i = zr_fix2long(from)
  while i < n && zr_space_byte_p(Machine.word(Machine.load8(RString.ptr(s) + i, 0)), nul)
    i += 1
  end
  zr_fix(i)
end

# The first offset at or after `from` whose byte splits words, or the
# length.
sig [Value, Value] => Value
machine def zr_str_word_end(s, from)
  n = RString.len(s)
  i = zr_fix2long(from)
  while i < n && !zr_space_byte_p(Machine.word(Machine.load8(RString.ptr(s) + i, 0)), Machine.value(QFALSE))
    i += 1
  end
  zr_fix(i)
end

# Where the whitespace that ends at offset `to` starts.
sig [Value, Value, Value] => Value
machine def zr_str_space_start(s, to, nul)
  i = zr_fix2long(to)
  while i > 0 && zr_space_byte_p(Machine.word(Machine.load8(RString.ptr(s) + i - 1, 0)), nul)
    i -= 1
  end
  zr_fix(i)
end

# One byte appended as it is, the flags untouched (`append_as_bytes`).
sig [Value, Value] => Value
machine def zr_str_push_byte(recv, byte)
  if zr_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  n = RString.len(recv) + 1
  if n + 1 > RString.capa(recv)
    capa = RString.capa(recv) * 2
    if capa < n + 1
      capa = n + 1
    end
    p = zr_xmalloc(capa)
    zr_memcpy(p, RString.ptr(recv), RString.len(recv))
    free(RString.ptr(recv))
    RString.set_ptr(recv, p)
    RString.set_capa(recv, capa)
  end
  Machine.store8(RString.ptr(recv) + RString.len(recv), 0, Machine.i8(zr_fix2long(byte)))
  RString.set_len(recv, n)
  Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
  if (zr_fix2long(byte) & 255) >= 128
    zr_str_modified(recv)
  end
  if zr_str_encoding_index(recv) == ENC_USASCII && zr_fix2long(byte) >= 128
    zr_str_set_index(recv, ENC_UTF8)
  end
  recv
end

# Where a string's bytes sit, for the `p` and `P` pack directives.
sig [Value] => Value
machine def zr_str_bytes_address(s)
  zr_fix(Machine.word(RString.ptr(s)))
end
