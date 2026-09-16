# Strings: a length, a capacity and a buffer outside the arena.
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr

# A String whose bytes live in its own cell, after the header, with
# room for STR_EMBED_CAPA of them and a NUL. A longer String keeps
# them in a malloc'd buffer of `capa` + 1 bytes. Either way `ptr`
# reaches the bytes and `capa` counts the room, so a reader never
# asks which.
FL_EMBED = 1 << 7
FL_EMBED_CLEAR = 0 - FL_EMBED - 1
STR_EMBED_CAPA = CELL - 40 - 1

sig [Value] => Bool
machine def zr_str_embedded_p(s)
  (RBasic.flags(s) & FL_EMBED) != 0
end

# A buffer with room for `n` bytes and a NUL for `s`, whose old bytes
# are gone: the cell's own tail when they fit, else a malloc'd one.
sig [Value, Word] => Void
machine def zr_str_buf_new(s, n)
  if n <= STR_EMBED_CAPA
    RString.set_ptr(s, Machine.ptr(s) + RString.size)
    RString.set_capa(s, STR_EMBED_CAPA)
    RBasic.set_flags(s, RBasic.flags(s) | FL_EMBED)
  else
    RString.set_ptr(s, zr_xmalloc(n + 1))
    RString.set_capa(s, n)
    RBasic.set_flags(s, RBasic.flags(s) & FL_EMBED_CLEAR)
  end
end

# The buffer given back when it is malloc'd; the cell's own tail goes
# with the cell.
sig [Value] => Void
machine def zr_str_buf_free(s)
  if !zr_str_embedded_p(s) && RString.ptr(s) != 0
    zr_xfree(RString.ptr(s))
  end
end

# Room for `n` bytes and a NUL, the bytes kept. A buffer that grows
# leaves the cell and doubles from then on.
sig [Value, Word] => Void
machine def zr_str_reserve(s, n)
  if n <= RString.capa(s)
    return
  end
  capa = RString.capa(s) * 2
  if capa < n
    capa = n
  end
  p = zr_xmalloc(capa + 1)
  zr_memcpy(p, RString.ptr(s), RString.len(s))
  zr_str_buf_free(s)
  RString.set_ptr(s, p)
  RString.set_capa(s, capa)
  RBasic.set_flags(s, RBasic.flags(s) & FL_EMBED_CLEAR)
end


# A String whose bytes a scan found all below 0x80, which CRuby calls
# the 7-bit coderange. Every write to the bytes clears it, so a String
# read many times is scanned once.
FL_ASCII = 1 << 21
# A String a scan found valid in its encoding, CRuby's valid coderange.
# The same writes clear it, and so does a new encoding.
FL_VALID = 1 << 23
FL_ASCII_CLEAR = 0 - FL_ASCII - 1
FL_SCANS_CLEAR = 0 - FL_ASCII - FL_VALID - 1

# The bytes of `s` changed: what a scan found about them is gone.
sig [Value] => Void
machine def zr_str_modified(s)
  RBasic.set_flags(s, RBasic.flags(s) & FL_SCANS_CLEAR)
end

sig [Ptr, Word] => Value
machine def zr_str_new(bytes, len)
  s = zr_alloc(T_STRING, zr_global(G_STRING))
  zr_str_buf_new(s, len)
  zr_memcpy(RString.ptr(s), bytes, len)
  Machine.store8(RString.ptr(s) + len, 0, Machine.i8(0))
  RString.set_len(s, len)
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
  zr_str_take_bytes(recv, src)
  zr_str_modified(recv)
  zr_str_copy_encoding(recv, src)
end

# `src`'s bytes in place of `recv`'s own, in a buffer of their size;
# a String is its own source already.
sig [Value, Value] => Void
machine def zr_str_take_bytes(recv, src)
  if Machine.word(recv) == Machine.word(src)
    return
  end
  n = RString.len(src)
  zr_str_buf_free(recv)
  zr_str_buf_new(recv, n)
  zr_memcpy(RString.ptr(recv), RString.ptr(src), n)
  Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
  RString.set_len(recv, n)
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
    zr_buf_free(b)
    return s
  end
  zr_buf_str(b, s)
  e = zr_exc_new(zr_global(G_FROZEN_ERROR), zr_buf_take(b))
  zr_exc_detail(e, Machine.id(:receiver), v)
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
  flags = (RBasic.flags(s) & FL_ENC_KEEP & (0 - FL_VALID - 1)) | (i << FL_ENC_SHIFT)
  # ASCII bytes are not ASCII text in UTF-16 or UTF-32.
  if !zr_enc_ascii_compat_p(index)
    flags = flags & FL_ASCII_CLEAR
  end
  RBasic.set_flags(s, flags)
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

# Whether the String writes its characters as UTF-8 writes them: in
# UTF-8, or in UTF8-MAC or a carrier's UTF-8, which differ from it only
# in the characters they convert.
sig [Value] => Bool
machine def zr_str_wide_p(s)
  index = zr_str_encoding_index(s)
  index == ENC_UTF8 || zr_enc_utf8_like_p(index)
end

# Whether the String holds characters that span bytes in a way of their
# own: one of the multibyte encodings rt/kernel/enc_mb.rb carries.
sig [Value] => Bool
machine def zr_str_mb_p(s)
  zr_enc_mb_p(zr_str_encoding_index(s))
end

# The byte length of the character at byte `off` of a multibyte String,
# or 0 when those bytes are no whole character: a lead byte the
# encoding has no use for, a byte that cannot follow it, or a character
# the text ends in the middle of.
sig [Value, Word] => Word
machine def zr_str_mb_len(s, off)
  index = zr_str_encoding_index(s)
  p = RString.ptr(s) + off
  rest = RString.len(s) - off
  lead = Machine.word(Machine.load8(p, 0))
  if lead < 128
    return 1
  end
  second = rest > 1 ? Machine.word(Machine.load8(p + 1, 0)) : 0
  n = zr_mb_lead_len(index, lead, second)
  if n < 2
    return n
  end
  if rest < n
    return 0
  end
  i = 1
  while i < n
    if !zr_mb_trail_ok(index, lead, i, Machine.word(Machine.load8(p + i, 0)))
      return 0
    end
    i += 1
  end
  n
end

# The stop a String whose bytes make no character raises. Encoding
# writes it, because the names live there.
sig [Value] => Value
machine def zr_str_bad_bytes(s)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(s))
  zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:invalid_bytes), 1, slot)
end

# Whether an ASCII byte is an ASCII character in the encoding `index`
# names: in every one but UTF-16 and UTF-32, dummy names included.
sig [Word] => Bool
machine def zr_enc_ascii_compat_p(index)
  index < ENC_UTF16BE || index > ENC_UTF32
end

# The width of a code unit of UTF-16 (2) and UTF-32 (4), the Unicode
# encodings a String walks by units; 0 for every other.
sig [Value] => Word
machine def zr_str_unit(s)
  i = zr_str_encoding_index(s)
  if i == ENC_UTF16BE || i == ENC_UTF16LE
    return 2
  end
  if i == ENC_UTF32BE || i == ENC_UTF32LE
    return 4
  end
  0
end

# The code unit at byte `off`, read in the String's byte order.
sig [Value, Word, Word] => Word
machine def zr_str_unit_at(s, off, unit)
  i = zr_str_encoding_index(s)
  big = i == ENC_UTF16BE || i == ENC_UTF32BE
  v = 0
  k = 0
  while k < unit
    at = big ? k : unit - 1 - k
    v = (v << 8) | Machine.word(Machine.load8(RString.ptr(s) + off + at, 0))
    k += 1
  end
  v
end

# The byte length of the character at byte `off` of a UTF-16 or UTF-32
# String: one code unit, a surrogate pair in UTF-16, or what is left
# when that is less.
sig [Value, Word, Word] => Word
machine def zr_unit_char_len(s, off, unit)
  rest = RString.len(s) - off
  if rest < unit
    return rest
  end
  if unit == 2 && rest >= 4
    high = zr_str_unit_at(s, off, 2)
    if high >= 55296 && high <= 56319
      low = zr_str_unit_at(s, off + 2, 2)
      if low >= 56320 && low <= 57343
        return 4
      end
    end
  end
  unit
end

# Whether that character is a whole one: no lone surrogate, no UTF-32
# unit past Unicode, no short tail.
sig [Value, Word, Word, Word] => Bool
machine def zr_unit_char_valid_p(s, off, len, unit)
  if len < unit
    return false
  end
  if len == 4 && unit == 2
    return true
  end
  v = zr_str_unit_at(s, off, unit)
  (v < 55296 || v > 57343) && v <= 1114111
end

# The code point of a whole character.
sig [Value, Word, Word, Word] => Word
machine def zr_unit_point(s, off, len, unit)
  if unit == 2 && len == 4
    high = zr_str_unit_at(s, off, 2)
    low = zr_str_unit_at(s, off + 2, 2)
    return 65536 + ((high - 55296) << 10) + (low - 56320)
  end
  zr_str_unit_at(s, off, unit)
end

sig [Ptr, Word] => Void
machine def zr_buf_unit_name(b, index)
  if index == ENC_UTF16BE
    zr_buf_push(b, Machine.bytes("UTF-16BE"), 8)
  elsif index == ENC_UTF16LE
    zr_buf_push(b, Machine.bytes("UTF-16LE"), 8)
  elsif index == ENC_UTF32BE
    zr_buf_push(b, Machine.bytes("UTF-32BE"), 8)
  else
    zr_buf_push(b, Machine.bytes("UTF-32LE"), 8)
  end
end

# `clear`, and what `String#initialize` does with a capacity and no
# source: no bytes left, in the encoding the String already had.
sig [Value] => Value
machine def zr_str_discard(s)
  if zr_modify_frozen_p(s)
    return zr_frozen_error(s)
  end
  RString.set_len(s, 0)
  Machine.store8(RString.ptr(s), 0, Machine.i8(0))
  zr_str_modified(s)
  s
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

# A String the core library writes out of plain ASCII -- digits, a
# name, brackets -- which is US-ASCII, as rb_usascii_str_new makes it.
sig [Ptr, Word] => Value
machine def zr_usascii_str_new(bytes, len)
  zr_str_set_index(zr_str_new(bytes, len), ENC_USASCII)
end

# `s` tagged US-ASCII, for text the core library knows is plain ASCII.
sig [Value] => Value
machine def zr_str_usascii(s)
  zr_str_set_index(s, ENC_USASCII)
end

# The encoding a String takes when a piece is appended to it, as
# rb_enc_cr_str_buf_cat decides. The String is `len` bytes in `index`,
# all of them ASCII when `ascii`; the piece is in `piece`, all ASCII
# when `piece_ascii`, and holds a byte. ENC_NONE when the two cannot
# join.
sig [Word, Bool, Word, Word, Bool] => Word
machine def zr_enc_append(index, ascii, len, piece, piece_ascii)
  if piece == index
    return index
  end
  if !zr_enc_ascii_compat_p(index) || !zr_enc_ascii_compat_p(piece)
    return len == 0 ? piece : ENC_NONE
  end
  if piece_ascii
    return index
  end
  ascii ? piece : ENC_NONE
end

# The same for a String piece, which an empty one leaves as it was.
sig [Word, Bool, Word, Value] => Word
machine def zr_enc_append_str(index, ascii, len, s)
  if RString.len(s) == 0
    return index
  end
  zr_enc_append(index, ascii, len, zr_str_encoding_index(s), zr_str_ascii_bytes_p(s))
end

# The encoding a join takes, as rb_enc_compatible decides: an empty
# side gives way, unless the receiver is empty and the other side is
# not ASCII it can hold; else the side that is not plain ASCII. Both
# sides plain ASCII gives the receiver's, so `"a" + "b".b` stays text.
sig [Value, Value] => Word
machine def zr_str_join_index(a, b)
  ia = zr_str_encoding_index(a)
  if ia == zr_str_encoding_index(b) || RString.len(b) == 0
    return ia
  end
  if RString.len(a) == 0
    return zr_enc_ascii_compat_p(ia) && zr_str_ascii_bytes_p(b) ? ia : zr_str_encoding_index(b)
  end
  zr_str_ascii_bytes_p(b) ? ia : zr_str_encoding_index(b)
end

# Whether joining `a` and `b` is ruby's compatibility error: two
# encodings and neither side empty, with either side in UTF-16 or
# UTF-32 or a byte past ASCII on each.
sig [Value, Value] => Bool
machine def zr_str_join_incompatible_p(a, b)
  ia = zr_str_encoding_index(a)
  ib = zr_str_encoding_index(b)
  if ia == ib || RString.len(a) == 0 || RString.len(b) == 0
    return false
  end
  if !zr_enc_ascii_compat_p(ia) || !zr_enc_ascii_compat_p(ib)
    return true
  end
  !zr_str_ascii_bytes_p(a) && !zr_str_ascii_bytes_p(b)
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
  if !zr_enc_ascii_compat_p(zr_str_encoding_index(s))
    return false
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
  index = zr_str_join_index(recv, other)
  zr_str_set_index(zr_buf_take(b), index)
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
  if zr_str_unit(recv) != 0
    # UTF-16 and UTF-32 write a code point in Ruby, where the code
    # units and their byte order are.
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(zr_fix(c)))
    return zr_send(recv, Machine.id(:append_unit_point), 1, arg)
  end
  # A multibyte encoding writes a code point as the bytes that spell it,
  # in Ruby, where its tables are, and so does UTF-8 by another name,
  # which a failure names.
  if zr_enc_mb_p(zr_str_encoding_index(recv)) || zr_enc_utf8_like_p(zr_str_encoding_index(recv))
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(zr_fix(c)))
    return zr_send(recv, Machine.id(:append_mb_point), 1, arg)
  end
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
    if zr_modify_frozen_p(recv)
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

# `other`'s bytes onto `recv`, whatever either's encoding: an IO's
# write buffer takes text as bytes.
sig [Value, Value] => Value
machine def zr_str_cat_bytes(recv, other)
  n = RString.len(recv) + RString.len(other)
  zr_str_reserve(recv, n)
  zr_memcpy(RString.ptr(recv) + RString.len(recv), RString.ptr(other), RString.len(other))
  RString.set_len(recv, n)
  Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
  zr_str_modified(recv)
  recv
end

# `<<` appends in place; a frozen receiver raises.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_concat(recv, argc, argv, cref, blk)
  if zr_modify_frozen_p(recv)
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
  zr_str_reserve(recv, n)
  zr_memcpy(RString.ptr(recv) + RString.len(recv), RString.ptr(other), RString.len(other))
  RString.set_len(recv, n)
  Machine.store8(RString.ptr(recv) + n, 0, Machine.i8(0))
  if !ascii
    zr_str_modified(recv)
  end
  zr_str_set_index(recv, index)
  recv
end

# `concat`: the arguments appended in order, as `<<` appends one. Two
# or more are joined first, as CRuby joins them, so `s.concat(s, s)`
# appends `s` as it was and a bad argument appends nothing.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_concat_m(recv, argc, argv, cref, blk)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  if argc < 2
    return argc == 0 ? recv : zr_str_concat(recv, argc, argv, cref, blk)
  end
  joined = zr_str_new(Machine.bytes(""), 0)
  zr_str_set_index(joined, zr_str_encoding_index(recv))
  i = 0
  while i < argc
    r = zr_str_concat(joined, 1, argv + (i * 8), cref, blk)
    return r if r == QUNDEF
    i += 1
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(joined))
  zr_str_concat(recv, 1, slot, cref, blk)
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
    return zr_str_cmp_other(recv, other)
  end
  r = zr_bytes_cmp(RString.ptr(recv), RString.len(recv), RString.ptr(other), RString.len(other))
  if r != 0 || zr_str_comparable(recv, other)
    return zr_fix(r)
  end
  a = zr_str_encoding_index(recv)
  b = zr_str_encoding_index(other)
  zr_fix(a < b ? 0 - 1 : 1)
end

# rb_str_cmp_m for an operand that is no String: what its `to_str`
# answers compares, else the operand's own `<=>` with the receiver,
# turned round, as rb_invcmp asks it.
sig [Value, Value] => Value
machine def zr_str_cmp_other(recv, other)
  slot = Machine.slot(8)
  if !zr_special_p(other) && zr_find_method(zr_class_of(other), Machine.id(:to_str)) != 0
    s = zr_send(other, Machine.id(:to_str), 0, 0)
    return s if s == QUNDEF
    if !zr_special_p(s) && zr_type(s) == T_STRING
      Machine.store64(slot, 0, Machine.word(s))
      return zr_str_cmp(recv, 1, slot, Machine.value(QNIL), Machine.value(QNIL))
    end
  end
  Machine.store64(slot, 0, Machine.word(recv))
  r = zr_send(other, Machine.id(:<=>), 1, slot)
  if r == QUNDEF || r == QNIL
    return r
  end
  sign = zr_cmpint(r, other, recv)
  return sign if sign == QUNDEF
  zr_fix(0 - zr_fix2long(sign))
end

# Two strings compare only when they hold one encoding, or when both
# are ASCII throughout.
sig [Value, Value] => Bool
machine def zr_str_comparable(a, b)
  zr_str_encoding_index(a) == zr_str_encoding_index(b) || RString.len(a) == 0 || RString.len(b) == 0 || (zr_str_ascii_only(a) && zr_str_ascii_only(b))
end

# What `zr_str_ascii_bytes_p` answers, and the name the rest of the
# kernel asks by. It used to walk the bytes itself and remember nothing,
# so a String-keyed Hash scanned every key twice on every lookup -- once
# to hash it and once to ask this -- and asked again the next time.
# `FL_ASCII` is cleared by `zr_str_modified` and by an encoding that
# cannot hold ASCII text, so the memo is never stale.
sig [Value] => Bool
machine def zr_str_ascii_only(s)
  zr_str_ascii_bytes_p(s)
end

# `String#ascii_only?`, over the same memo.
sig [Value] => Value
machine def zr_str_ascii_only_m(s)
  zr_bool(zr_str_ascii_bytes_p(s))
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

# A frozen copy that keeps a subclass, as rb_str_new_frozen makes one:
# what a MatchData holds of the text it matched.
sig [Value] => Value
machine def zr_str_new_frozen_m(s)
  copy = zr_str_copy_encoding(zr_str_new(RString.ptr(s), RString.len(s)), s)
  RBasic.set_klass(copy, zr_real_class(s))
  RBasic.set_flags(copy, RBasic.flags(copy) | FL_FREEZE)
  copy
end

# The character count for core code that must not dispatch.
sig [Value] => Value
machine def zr_str_length_m(s)
  zr_fix(zr_str_char_count(s))
end

# Whether every byte is a character of its own: a byte-oriented
# encoding, or text with no byte past ASCII.
sig [Value] => Bool
machine def zr_str_bytes_are_chars(s)
  if zr_str_unit(s) != 0
    return RString.len(s) == 0
  end
  if !zr_str_wide_p(s) && !zr_str_mb_p(s)
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
# sequence, a UTF-16 or UTF-32 character, else the one byte.
sig [Value, Word] => Word
machine def zr_str_char_len_at(s, off)
  # The flag alone, never a scan: this runs once for each character.
  if (RBasic.flags(s) & FL_ASCII) != 0
    return 1
  end
  if !zr_str_wide_p(s)
    unit = zr_str_unit(s)
    if unit != 0
      return zr_unit_char_len(s, off, unit)
    end
    if zr_str_mb_p(s)
      wide = zr_str_mb_len(s, off)
      return wide == 0 ? 1 : wide
    end
    return 1
  end
  len = zr_utf8_char_len(RString.ptr(s) + off, RString.len(s) - off)
  len == 0 ? 1 : len
end

sig [Value] => Word
machine def zr_str_char_count(s)
  n = RString.len(s)
  # A scan that found the bytes ASCII answers first: one flag test.
  if (RBasic.flags(s) & FL_ASCII) != 0 || (!zr_str_wide_p(s) && zr_str_unit(s) == 0 && !zr_str_mb_p(s)) || zr_str_ascii_bytes_p(s)
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
  if (RBasic.flags(s) & FL_ASCII) != 0 || (!zr_str_wide_p(s) && zr_str_unit(s) == 0 && !zr_str_mb_p(s)) || zr_str_ascii_bytes_p(s)
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

# The code point CESU-8 writes in the `width` bytes at `p`: two or three
# bytes as UTF-8 writes them, or six that hold a pair of surrogates.
sig [Ptr, Word] => Word
machine def zr_cesu8_point(p, width)
  if width == 2
    return ((Machine.word(Machine.load8(p, 0)) & 31) << 6) | (Machine.word(Machine.load8(p + 1, 0)) & 63)
  end
  high = ((Machine.word(Machine.load8(p, 0)) & 15) << 12) | ((Machine.word(Machine.load8(p + 1, 0)) & 63) << 6) | (Machine.word(Machine.load8(p + 2, 0)) & 63)
  if width < 6
    return high
  end
  low = ((Machine.word(Machine.load8(p + 4, 0)) & 63) << 6) | (Machine.word(Machine.load8(p + 5, 0)) & 63)
  65536 + ((high - 55296) << 10) + (low & 1023)
end

# The code point of the first character.
sig [Value] => Value
machine def zr_str_ord(s)
  n = RString.len(s)
  if n == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("empty string"), 12)
  end
  unit = zr_str_unit(s)
  if unit != 0
    width = zr_unit_char_len(s, 0, unit)
    if !zr_unit_char_valid_p(s, 0, width, unit)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("invalid byte sequence in "), 25)
      zr_buf_unit_name(b, zr_str_encoding_index(s))
      return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
    end
    return zr_fix(zr_unit_point(s, 0, width, unit))
  end
  p = RString.ptr(s)
  c = Machine.word(Machine.load8(p, 0))
  # A multibyte encoding gives its characters the number their own bytes
  # spell, as rb_enc_codepoint does: EUC-JP's A4 A2 is 42146.
  if c >= 128 && zr_str_mb_p(s)
    width = zr_str_mb_len(s, 0)
    if width == 0
      return zr_str_bad_bytes(s)
    end
    if zr_str_encoding_index(s) == ENC_CESU8
      return zr_fix(zr_cesu8_point(p, width))
    end
    v = 0
    k = 0
    while k < width
      v = (v << 8) | Machine.word(Machine.load8(p + k, 0))
      k += 1
    end
    return zr_fix(v)
  end
  if c < 128 || !zr_str_wide_p(s)
    return zr_fix(c)
  end
  len = zr_utf8_char_len(p, n)
  if len == 0
    return zr_str_bad_bytes(s)
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
  if (RBasic.flags(s) & FL_VALID) != 0
    return Machine.value(QTRUE)
  end
  valid = zr_str_valid_scan(s)
  if valid == QTRUE
    RBasic.set_flags(s, RBasic.flags(s) | FL_VALID)
  end
  valid
end

sig [Value] => Value
machine def zr_str_valid_scan(s)
  if zr_str_encoding_index(s) == ENC_USASCII
    return zr_bool(zr_str_ascii_bytes_p(s))
  end
  unit = zr_str_unit(s)
  if unit != 0
    at = 0
    while at < RString.len(s)
      width = zr_unit_char_len(s, at, unit)
      if !zr_unit_char_valid_p(s, at, width, unit)
        return Machine.value(QFALSE)
      end
      at += width
    end
    return Machine.value(QTRUE)
  end
  if zr_str_mb_p(s)
    stop = RString.len(s)
    at = 0
    while at < stop
      width = zr_str_mb_len(s, at)
      if width == 0
        return Machine.value(QFALSE)
      end
      at += width
    end
    return Machine.value(QTRUE)
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
  zr_bytes_find(RString.ptr(hay), RString.len(hay), RString.ptr(needle), RString.len(needle), from)
end

Machine.import "memmem", [Ptr, Word, Ptr, Word] => Ptr

# The `m` bytes at `needle` in the `n` at `hay`, at or after byte
# `from`: the offset, or -1. An empty needle is found at `from`, which
# is not every libc's memmem answer over an empty rest.
sig [Ptr, Word, Ptr, Word, Word] => Word
machine def zr_bytes_find(hay, n, needle, m, from)
  if from + m > n
    return 0 - 1
  end
  if m == 0
    return from
  end
  p = memmem(hay + from, n - from, needle, m)
  if p == 0
    return 0 - 1
  end
  p - hay
end

# `s.split(sep)` by a String's bytes: the piece before each match and,
# past the last, the rest (kept under a limit, or when it is not
# empty); a `limit` above 0 caps the pieces. The core checks the
# encodings and the bytes first, and drops trailing empty pieces for
# a limit of 0.
sig [Value, Value, Value] => Value
machine def zr_str_split_by(s, sep, limit_v)
  limit = zr_fix2long(limit_v)
  n = RString.len(s)
  m = RString.len(sep)
  out = zr_ary_new(8)
  beg = 0
  pieces = 1
  while limit <= 0 || pieces < limit
    i = zr_bytes_find(RString.ptr(s), n, RString.ptr(sep), m, beg)
    if i < 0
      break
    end
    zr_ary_push(out, zr_str_copy_encoding(zr_str_new(RString.ptr(s) + beg, i - beg), s))
    beg = i + m
    pieces += 1
  end
  if n > 0 && (limit != 0 || n > beg)
    zr_ary_push(out, zr_str_copy_encoding(zr_str_new(RString.ptr(s) + beg, n - beg), s))
  end
  # No limit drops the empty pieces at the end.
  if limit == 0
    while RArray.len(out) > 0 && RString.len(zr_ary_at(out, RArray.len(out) - 1)) == 0
      RArray.set_len(out, RArray.len(out) - 1)
    end
  end
  out
end

# `split` with no pattern or " ": the pieces between runs of blanks,
# the leading blanks skipped, and what follows the last piece kept
# under a limit, as split_words reads them.
sig [Value, Value] => Value
machine def zr_str_split_words(s, limit_v)
  limit = zr_fix2long(limit_v)
  n = RString.len(s)
  out = zr_ary_new(8)
  beg = 0
  while beg < n && zr_blank_byte_p(Machine.word(Machine.load8(RString.ptr(s) + beg, 0)))
    beg += 1
  end
  while beg < n
    if limit > 0 && limit <= RArray.len(out) + 1
      break
    end
    stop = beg
    while stop < n && !zr_blank_byte_p(Machine.word(Machine.load8(RString.ptr(s) + stop, 0)))
      stop += 1
    end
    if stop == n
      break
    end
    zr_ary_push(out, zr_str_copy_encoding(zr_str_new(RString.ptr(s) + beg, stop - beg), s))
    beg = stop
    while beg < n && zr_blank_byte_p(Machine.word(Machine.load8(RString.ptr(s) + beg, 0)))
      beg += 1
    end
  end
  if n > 0 && (limit != 0 || n > beg)
    zr_ary_push(out, zr_str_copy_encoding(zr_str_new(RString.ptr(s) + beg, n - beg), s))
  end
  out
end

# Whether `sep` is the one String that splits on blanks: " ".
sig [Value] => Value
machine def zr_str_blank_sep_p(sep)
  if zr_special_p(sep) || zr_type(sep) != T_STRING
    return Machine.value(QFALSE)
  end
  zr_bool(RString.len(sep) == 1 && Machine.word(Machine.load8(RString.ptr(sep), 0)) == 32)
end

# Whether `sep` is a String that splits by its bytes: not empty, which
# splits into characters, and not " ", which splits on blanks.
sig [Value] => Value
machine def zr_str_plain_sep_p(sep)
  if zr_special_p(sep) || zr_type(sep) != T_STRING
    return Machine.value(QFALSE)
  end
  n = RString.len(sep)
  zr_bool(n > 1 || (n == 1 && Machine.word(Machine.load8(RString.ptr(sep), 0)) != 32))
end

# `s.to_i` in base 10 when the answer is a fixnum: leading blanks (C's
# isspace, so not NUL, which the core's strip counts), a sign, digits
# with single underscores between them, stopping at the first other
# byte. nil leaves the rest to the core: a `0d` prefix, or a number
# past 18 digits.
sig [Value] => Value
machine def zr_str_to_i10(s)
  p = RString.ptr(s)
  n = RString.len(s)
  i = 0
  while i < n && zr_blank_byte_p(Machine.word(Machine.load8(p + i, 0)))
    i += 1
  end
  negative = false
  if i < n
    b = Machine.word(Machine.load8(p + i, 0))
    if b == 45 || b == 43
      negative = b == 45
      i += 1
    end
  end
  v = 0
  digits = 0
  start = i
  while i < n
    b = Machine.word(Machine.load8(p + i, 0))
    if zr_digit_byte_p(b)
      v = (v * 10) + (b - 48)
      digits += 1
      if digits > 18
        return Machine.value(QNIL)
      end
      i += 1
    elsif b == 95 && digits > 0 && i + 1 < n && zr_digit_byte_p(Machine.word(Machine.load8(p + i + 1, 0)))
      i += 1
    else
      break
    end
  end
  # `0d12`: a prefix the core reads, not a zero.
  if digits == 1 && i == start + 1 && v == 0 && i < n
    b = Machine.word(Machine.load8(p + i, 0))
    if b == 100 || b == 68
      return Machine.value(QNIL)
    end
  end
  zr_fix(negative ? 0 - v : v)
end

sig [Word] => Bool
machine def zr_blank_byte_p(b)
  b == 32 || (b >= 9 && b <= 13)
end

sig [Word] => Bool
machine def zr_digit_byte_p(b)
  b >= 48 && b <= 57
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

# `to_sym`: a Symbol is its bytes and their encoding, as rb_str_intern
# keys it. ASCII bytes name one Symbol in every encoding; bytes invalid
# in theirs name none.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_to_sym(recv, argc, argv, cref, blk)
  if zr_str_ascii_bytes_p(recv)
    return zr_sym(zr_intern(RString.ptr(recv), RString.len(recv)))
  end
  if zr_str_valid_p(recv) == QFALSE
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("invalid symbol in encoding "), 27)
    if zr_str_wide_p(recv)
      zr_buf_push(b, Machine.bytes("UTF-8"), 5)
    else
      zr_buf_push(b, Machine.bytes("US-ASCII"), 8)
    end
    zr_buf_push(b, Machine.bytes(" :"), 2)
    s = zr_inspect(recv)
    return s if s == QUNDEF
    zr_buf_str(b, s)
    return zr_raise_buf(zr_core_class(Machine.id(:EncodingError)), b)
  end
  tag = (RBasic.flags(recv) >> FL_ENC_SHIFT) & 255
  zr_sym(zr_intern_tagged(RString.ptr(recv), RString.len(recv), tag))
end

# `+str`: the string itself unless frozen or chilled, then a copy that is not,
# with its encoding and class, as rb_str_dup makes it.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_str_uplus(recv, argc, argv, cref, blk)
  if zr_frozen_p(recv) || zr_str_chilled_p(recv)
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
    RBasic.set_flags(recv, (RBasic.flags(recv) | FL_FREEZE) & (zr_type(recv) == T_STRING ? FL_CHILLED_CLEAR : 0 - 1))
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
# result starts in the first piece's encoding and each piece joins it
# as rb_str_buf_append joins one -- a piece past ASCII moves a result
# that is plain ASCII to its own encoding, and two pieces past ASCII in
# two encodings are an error -- while a result in US-ASCII takes the
# encoding of any piece that is not (rb_str_concat_literals).
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
        zr_buf_free(b)
        return s
      end
    end
    if zr_special_p(s) || zr_type(s) != T_STRING
      s = zr_str_from_buf_obj_head(v)
    end
    piece = zr_str_encoding_index(s)
    joined = i == 0 ? piece : zr_enc_append_str(index, ascii, Buf.len(b), s)
    if joined == ENC_NONE
      return zr_str_join_incompatible(zr_str_set_index(zr_buf_take(b), index), s)
    end
    index = piece != ENC_USASCII && joined == ENC_USASCII ? piece : joined
    ascii = ascii && zr_str_ascii_bytes_p(s)
    zr_buf_str(b, s)
    i += 1
  end
  zr_str_set_index(zr_buf_take(b), index)
end

# The plain object form, `#<Class:0x...>`, as a String.
sig [Value] => Value
machine def zr_str_from_buf_obj_head(v)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_obj_head(b, v)
  zr_buf_byte(b, 62)
  zr_buf_take_at(b, ENC_BINARY)
end

# A frozen literal: the same String object at every evaluation.
sig [Ptr, Word] => Value
machine def zr_str_frozen(bytes, len)
  zr_str_intern(zr_str_new(bytes, len))
end

# A String a literal made in a file that sets no frozen_string_literal
# (STR_CHILLED_LITERAL), or that `Symbol#to_s` made
# (STR_CHILLED_SYMBOL_TO_S). It is not frozen, but its first change
# warns that it will be, and it is an ordinary String from then on.
FL_CHILLED = 1 << 15
FL_CHILLED_SYMBOL = 1 << 16
FL_CHILLED_CLEAR = 0 - FL_CHILLED - FL_CHILLED_SYMBOL - 1

sig [Ptr, Word] => Value
machine def zr_str_new_chilled(bytes, len)
  s = zr_str_new(bytes, len)
  RBasic.set_flags(s, RBasic.flags(s) | FL_CHILLED)
  s
end

sig [Ptr, Word, Word] => Value
machine def zr_str_new_chilled_at(bytes, len, index)
  s = zr_str_new_at(bytes, len, index)
  RBasic.set_flags(s, RBasic.flags(s) | FL_CHILLED)
  s
end

sig [Value] => Bool
machine def zr_str_chilled_p(s)
  !zr_special_p(s) && zr_type(s) == T_STRING && (RBasic.flags(s) & (FL_CHILLED | FL_CHILLED_SYMBOL)) != 0
end

# Whether a change to `v` is refused because `v` is frozen, as
# rb_check_frozen asks. A chilled String is changed, and warns first
# when deprecation warnings are on, as CHILLED_STRING_MUTATED does.
sig [Value] => Bool
machine def zr_modify_frozen_p(v)
  if zr_special_p(v)
    return true
  end
  flags = RBasic.flags(v)
  if (flags & T_MASK) == T_STRING && (flags & (FL_CHILLED | FL_CHILLED_SYMBOL)) != 0
    zr_str_unchill(v)
    flags = RBasic.flags(v)
  end
  (flags & FL_FREEZE) != 0
end

sig [Value] => Value
machine def zr_modify_frozen_m(v)
  zr_bool(zr_modify_frozen_p(v))
end

# `Warning[:deprecated]`, as the core last set it.
sig [Value] => Value
machine def zr_warn_deprecated_set(flag)
  Machine.store64(Machine.static(:warn_deprecated, 8), 0, flag == QNIL || flag == QFALSE ? 0 : 1)
  flag
end

sig [Value] => Void
machine def zr_str_unchill(s)
  symbol = (RBasic.flags(s) & FL_CHILLED_SYMBOL) != 0
  RBasic.set_flags(s, RBasic.flags(s) & FL_CHILLED_CLEAR)
  if Machine.load64(Machine.static(:warn_deprecated, 8), 0) == 0 || zr_gvar_get(Machine.id(:$VERBOSE)) == QNIL
    return
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  if symbol
    zr_buf_push(b, Machine.bytes("string returned by :"), 20)
    zr_buf_push(b, RString.ptr(s), RString.len(s))
    zr_buf_push(b, Machine.bytes(".to_s will be frozen in the future"), 34)
  else
    zr_buf_push(b, Machine.bytes("literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)"), 105)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(zr_buf_take(b)))
  r = zr_send(zr_const_get_at(zr_global(G_OBJECT), Machine.id(:Warning)), Machine.id(:deprecated), 1, slot)
  # The check that asked answers true or false, so a warning that raises
  # is dropped here.
  if r == QUNDEF
    Task.set_pending(zr_task(), Machine.value(QNIL))
  end
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
  zr_str_literal_shared(bytes, len)
end

G_FROZEN_LITERALS = 52

# The one frozen String of a UTF-8 literal, kept under the address its
# bytes sit at.
#
# `zr_str_frozen` already answers the same object at every evaluation --
# that is what the fstring table is for -- but it reaches it by making a
# String, copying the bytes, hashing them and throwing the new String
# away. Under `frozen_string_literal: true` that is an allocation, a
# malloc, a copy and a hash of every byte each time control passes a
# literal, which for a compiler is most of what it does.
#
# The key is the address of the bytes, which the emitter already hands
# in, so a hit is one hash of one word. The table is a rooted Hash, so
# the String it holds is marked.
#
# An address does not name a literal on its own: the eval road maps code
# at run time, and a freed mapping hands its addresses back. So a hit
# reads the bytes it found and keeps them only when they are the bytes
# that were asked for; a row that names something else is replaced. The
# check is a compare, not an allocation, and it is what makes a
# recycled address answer for the literal that is there now.
sig [Ptr, Word] => Value
machine def zr_str_literal_shared(bytes, len)
  table = zr_global(G_FROZEN_LITERALS)
  if zr_special_p(table)
    table = zr_hash_new()
    zr_set_global(G_FROZEN_LITERALS, table)
  end
  key = zr_fix(Machine.word(bytes))
  found = zr_hash_lookup(table, key)
  if found != QUNDEF && zr_bytes_eq(bytes, len, RString.ptr(found), RString.len(found))
    return found
  end
  s = zr_str_frozen(bytes, len)
  zr_hash_store(table, key, s)
  s
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
sig [Value, Word, Word, Ptr, Word] => Value
machine def zr_opt_ltlt(recv, mid, argc, argv, mode)
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
  zr_dispatch(0, recv, mid, argc, argv, mode, Machine.value(QNIL))
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
  # An index past the fixnums is past every String.
  if !zr_fixnum_p(i)
    return Machine.value(QNIL)
  end
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
  if zr_modify_frozen_p(s)
    return zr_frozen_error(s)
  end
  zr_str_take_bytes(s, other)
  zr_str_modified(s)
  zr_str_copy_encoding(s, other)
end

# `setbyte`: the byte at `i` becomes `byte` modulo 256.
sig [Value, Value, Value] => Value
machine def zr_str_setbyte(s, i, byte)
  if zr_modify_frozen_p(s)
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

# `[]=` and `insert` in place: the `len` bytes at `from` become `other`'s
# bytes, and what follows them moves once, as rb_str_update_1 splices. A
# copy of the whole string for each change made a loop of small patches
# quadratic in the string's size.
sig [Value, Value, Value, Value] => Value
machine def zr_str_splice(s, from, len, other)
  if zr_modify_frozen_p(s)
    return zr_frozen_error(s)
  end
  if zr_str_join_incompatible_p(s, other)
    return zr_str_join_incompatible(s, other)
  end
  index = zr_str_join_index(s, other)
  at = zr_fix2long(from)
  cut = zr_fix2long(len)
  m = RString.len(other)
  old = RString.len(s)
  n = old - cut + m
  # Its own bytes spliced into itself are read before any of them moves.
  src = RString.ptr(other)
  if Machine.word(other) == Machine.word(s)
    src = zr_xmalloc(m + 1)
    zr_memcpy(src, RString.ptr(s), m)
  end
  zr_str_reserve(s, n)
  if m != cut
    zr_memmove(RString.ptr(s) + at + m, RString.ptr(s) + at + cut, old - at - cut)
  end
  zr_memmove(RString.ptr(s) + at, src, m)
  if Machine.word(other) == Machine.word(s)
    zr_xfree(src)
  end
  RString.set_len(s, n)
  Machine.store8(RString.ptr(s) + n, 0, Machine.i8(0))
  zr_str_modified(s)
  zr_str_set_index(s, index)
  s
end

# One byte appended as it is, the flags untouched (`append_as_bytes`).
sig [Value, Value] => Value
machine def zr_str_push_byte(recv, byte)
  if zr_modify_frozen_p(recv)
    return zr_frozen_error(recv)
  end
  n = RString.len(recv) + 1
  zr_str_reserve(recv, n)
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
