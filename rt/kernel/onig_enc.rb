# The encodings Onigmo's matcher reads under ze0, with the helpers of
# regenc.c and enc/unicode.c the matcher calls. `enc` is the address
# of the encoding's descriptor inside the program
# (Regexp::Onig::Enc::Base#descriptor): its kind picks the primitives
# of the enc/*.c file it came from, and its tables hold what those read.
# Derived from Onigmo; the license is in rt/kernel/regexp.rb.
ONIG_ENC_KIND_SINGLE_BYTE = 0
ONIG_ENC_KIND_UTF8 = 1
ONIG_ENC_KIND_EUC_JP = 2
ONIG_ENC_KIND_SHIFT_JIS = 3
ONIG_ENC_KIND_TRAIL = 4
ONIG_ENC_KIND_EUC_KR = 5
ONIG_ENC_KIND_EUC_TW = 6
ONIG_ENC_KIND_GB18030 = 7
ONIG_ENC_KIND_EMACS_MULE = 8
ONIG_ENC_KIND_CESU8 = 9
ONIG_ENC_KIND_UTF16LE = 10
ONIG_ENC_KIND_UTF16BE = 11
ONIG_ENC_KIND_UTF32LE = 12
ONIG_ENC_KIND_UTF32BE = 13
ONIG_ENC_FLAG_SHARP_S = 1
ONIG_CTYPE_WORD_BIT = 4096
ONIG_MBC_CASE_FOLD_MAXLEN = 18
ONIG_CASE_FOLD_MULTI_CHAR = 1 << 30

# The descriptor's header; each table offset counts from the descriptor.
Machine.struct :OnigEnc,
  kind: Word, min_len: Word, max_len: Word, flags: Word,
  len_off: Word, trail_off: Word, lower_off: Word, word_off: Word, trans_off: Word, map_off: Word

sig [Word] => Word
machine def zr_onig_enc_kind(enc)
  OnigEnc.kind(Machine.ptr(enc))
end

# ONIGENC_IS_SINGLEBYTE
sig [Word] => Bool
machine def zr_onig_enc_single_byte_p(enc)
  OnigEnc.max_len(Machine.ptr(enc)) == 1
end

# Byte `i` of the table whose offset the descriptor's word at `field`
# holds (a byte offset into the header).
sig [Word, Word, Word] => Word
machine def zr_onig_enc_byte(enc, field, i)
  base = Machine.ptr(enc)
  off = Machine.word(Machine.load64(base + field, 0))
  Machine.word(Machine.load8(base + off + i, 0))
end

# trans[state][byte] of the encoding's state table: -1 accepts, -2 fails.
sig [Word, Word, Word] => Word
machine def zr_onig_enc_trans(enc, state, c)
  v = zr_onig_enc_byte(enc, 64, (state * 256) + c)
  v >= 128 ? v - 256 : v
end

# trans[state][byte] of utf_8.c: the next state, -1 to accept, -2 to fail.
sig [Word, Word] => Word
machine def zr_onig_utf8_trans(state, c)
  if state == 0
    return 0 - 1 if c < 128
    return 0 - 2 if c < 194
    return 1 if c < 224
    return 2 if c == 224
    return 4 if c == 237
    return 3 if c < 240
    return 5 if c == 240
    return 6 if c < 244
    return 7 if c == 244
    return 0 - 2
  end
  if state == 1
    return (c >= 128 && c < 192) ? 0 - 1 : 0 - 2
  end
  if state == 2
    return (c >= 160 && c < 192) ? 1 : 0 - 2
  end
  if state == 3
    return (c >= 128 && c < 192) ? 1 : 0 - 2
  end
  if state == 4
    return (c >= 128 && c < 160) ? 1 : 0 - 2
  end
  if state == 5
    return (c >= 144 && c < 192) ? 3 : 0 - 2
  end
  if state == 6
    return (c >= 128 && c < 192) ? 3 : 0 - 2
  end
  (c >= 128 && c < 144) ? 3 : 0 - 2
end

# mbc_enc_len (utf_8.c): the precise answer, n > 0 for a character of n
# bytes, -1 for an invalid sequence, -1-n when n more bytes are needed.
sig [Ptr, Ptr] => Word
machine def zr_onig_utf8_precise_len(p, e)
  return 0 - 1 if p >= e
  first = Machine.word(Machine.load8(p, 0))
  s = zr_onig_utf8_trans(0, first)
  if s < 0
    return s == 0 - 1 ? 1 : 0 - 1
  end
  need = Machine.word(Machine.load8(zr_onig_utf8_len() + first, 0))
  return 0 - 1 - (need - 1) if p + 1 == e
  s = zr_onig_utf8_trans(s, Machine.word(Machine.load8(p, 1)))
  if s < 0
    return s == 0 - 1 ? 2 : 0 - 1
  end
  return 0 - 1 - (need - 2) if p + 2 == e
  s = zr_onig_utf8_trans(s, Machine.word(Machine.load8(p, 2)))
  if s < 0
    return s == 0 - 1 ? 3 : 0 - 1
  end
  return 0 - 1 - (need - 3) if p + 3 == e
  s = zr_onig_utf8_trans(s, Machine.word(Machine.load8(p, 3)))
  s == 0 - 1 ? 4 : 0 - 1
end

# ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE's count when the text ends `k` bytes
# into a character that started with `first` in state `state`: each
# encoding's mbc_enc_len answers its own.
sig [Word, Word, Word, Word] => Word
machine def zr_onig_mb_need(enc, k, first, state)
  kind = zr_onig_enc_kind(enc)
  if kind == ONIG_ENC_KIND_GB18030
    return k == 1 ? 1 : 4 - k
  end
  if kind == ONIG_ENC_KIND_EUC_TW && k > 1
    return 4 - k
  end
  if kind == ONIG_ENC_KIND_CESU8
    return 6 - k if k > 2
    if k == 2 && state == 4
      return 4
    end
  end
  if kind == ONIG_ENC_KIND_TRAIL || kind == ONIG_ENC_KIND_EUC_KR
    return zr_onig_enc_byte(enc, 32, first) - 1
  end
  zr_onig_enc_byte(enc, 32, first) - k
end

# mbc_enc_len of the encodings that walk a state table from the lead
# byte (euc_jp.c, shift_jis.h, big5.c, gbk.c, cp949.c, euc_kr.c,
# euc_tw.c, gb18030.c, emacs_mule.c, cesu_8.c).
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_mb_precise_len(enc, p, e)
  return 0 - 1 if p >= e
  max = OnigEnc.max_len(Machine.ptr(enc))
  first = Machine.word(Machine.load8(p, 0))
  state = zr_onig_enc_trans(enc, 0, first)
  k = 1
  while true
    if state < 0
      return state == 0 - 1 ? k : 0 - 1
    end
    return 0 - 1 if k == max
    return 0 - 1 - zr_onig_mb_need(enc, k, first, state) if p + k == e
    state = zr_onig_enc_trans(enc, state, Machine.word(Machine.load8(p + k, 0)))
    k += 1
  end
  0 - 1
end

# UNICODE_VALID_CODEPOINT_P
sig [Word] => Bool
machine def zr_onig_valid_codepoint_p(c)
  return false if c > 1114111
  !(c < 65536 && ((c >> 8) & 248) == 216)
end

# mbc_enc_len of utf_16le.c, utf_16be.c, utf_32le.c and utf_32be.c.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_wide_precise_len(enc, p, e)
  kind = zr_onig_enc_kind(enc)
  len = Machine.word(e - p)
  if kind == ONIG_ENC_KIND_UTF16LE
    return 0 - 2 if len < 2
    byte = Machine.word(Machine.load8(p, 1))
    return 2 if (byte & 248) != 216
    if (byte & 252) == 216
      return 0 - 1 - (4 - len) if len < 4
      return 4 if (Machine.word(Machine.load8(p, 3)) & 252) == 220
    end
    return 0 - 1
  end
  if kind == ONIG_ENC_KIND_UTF16BE
    return 0 - 1 if len <= 0
    byte = Machine.word(Machine.load8(p, 0))
    if (byte & 248) != 216
      return len >= 2 ? 2 : 0 - 2
    end
    if (byte & 252) == 216
      return 0 - 4 if len == 1
      return 0 - 3 if len == 2
      if len == 3
        return 0 - 2 if (Machine.word(Machine.load8(p, 2)) & 252) == 220
        return 0 - 1
      end
      return 4 if (Machine.word(Machine.load8(p, 2)) & 252) == 220
    end
    return 0 - 1
  end
  return 0 - 1 if len < 0
  return 0 - 1 - (4 - len) if len < 4
  return 0 - 1 if !zr_onig_valid_codepoint_p(zr_onig_mbc_to_code(enc, p, e))
  4
end

# The precise_mbc_enc_len of the encoding.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_precise_len(enc, p, e)
  kind = zr_onig_enc_kind(enc)
  return zr_onig_utf8_precise_len(p, e) if kind == ONIG_ENC_KIND_UTF8
  return 1 if kind == ONIG_ENC_KIND_SINGLE_BYTE
  return zr_onig_wide_precise_len(enc, p, e) if kind >= ONIG_ENC_KIND_UTF16LE
  zr_onig_mb_precise_len(enc, p, e)
end

# onigenc_mbclen (regenc.c): the length clipped to the text.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_mbclen(enc, p, e)
  r = zr_onig_precise_len(enc, p, e)
  if r > 0
    return Machine.word(e - p) if p + r > e
    return r
  end
  return Machine.word(e - p) if r < 0 - 1
  p < e ? 1 : 0
end

# enclen (regenc.h): the encoding's one width when it has one.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_enclen(enc, p, e)
  base = Machine.ptr(enc)
  min = OnigEnc.min_len(base)
  if min == OnigEnc.max_len(base)
    return p < e ? min : 0
  end
  zr_onig_mbclen(enc, p, e)
end

# enclen_approx (regexec.c): onigenc_mbclen_approximate, the bytes a
# truncated character would have had.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_enclen_approx(enc, p, e)
  base = Machine.ptr(enc)
  min = OnigEnc.min_len(base)
  if min == OnigEnc.max_len(base)
    return p < e ? min : 0
  end
  r = zr_onig_precise_len(enc, p, e)
  return r if r > 0
  return Machine.word(e - p) + (0 - 1 - r) if r < 0 - 1
  1
end

# ONIGENC_IS_MBC_HEAD: whether the character at p is longer than a byte.
sig [Word, Ptr, Ptr] => Bool
machine def zr_onig_mbc_head_p(enc, p, e)
  zr_onig_mbclen(enc, p, e) != 1
end

# onigenc_mbn_mbc_to_code over `len` bytes.
sig [Ptr, Ptr, Word] => Word
machine def zr_onig_mbn_to_code(p, e, len)
  n = Machine.word(Machine.load8(p, 0))
  return n if len == 1
  i = 1
  while i < len
    break if p + i >= e
    n = (n << 8) + Machine.word(Machine.load8(p + i, 0))
    i += 1
  end
  n
end

# utf_8.c's mbc_to_code, the first byte for anything that is not a
# whole character.
sig [Ptr, Ptr] => Word
machine def zr_onig_utf8_to_code(p, e)
  c = Machine.word(Machine.load8(p, 0))
  len = zr_onig_utf8_precise_len(p, e)
  if len <= 1
    return 4294967295 - (255 - c) if c > 253
    return c
  end
  len -= 1
  n = c & ((1 << (6 - len)) - 1)
  i = 1
  while len > 0
    n = (n << 6) | (Machine.word(Machine.load8(p + i, 0)) & 63)
    i += 1
    len -= 1
  end
  n
end

# cesu_8.c's mbc_to_code.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_cesu8_to_code(enc, p, e)
  len = zr_onig_mb_precise_len(enc, p, e)
  c = Machine.word(Machine.load8(p, 0))
  return c if len == 1
  if len == 2
    return ((c & 31) << 6) | (Machine.word(Machine.load8(p, 1)) & 63)
  end
  if len == 3
    return zr_onig_decode3(p)
  end
  if len == 6
    return ((zr_onig_decode3(p) & 1023) << 10) + (zr_onig_decode3(p + 3) & 1023) + 65536
  end
  return 4294967295 - (255 - c) if c > 253
  c
end

# utf8_decode_3byte_sequence (cesu_8.c)
sig [Ptr] => Word
machine def zr_onig_decode3(p)
  ((Machine.word(Machine.load8(p, 0)) & 15) << 12) | ((Machine.word(Machine.load8(p, 1)) & 63) << 6) | (Machine.word(Machine.load8(p, 2)) & 63)
end

# ONIGENC_MBC_TO_CODE
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_mbc_to_code(enc, p, e)
  kind = zr_onig_enc_kind(enc)
  return Machine.word(Machine.load8(p, 0)) if kind == ONIG_ENC_KIND_SINGLE_BYTE
  return zr_onig_utf8_to_code(p, e) if kind == ONIG_ENC_KIND_UTF8
  if kind == ONIG_ENC_KIND_EUC_JP || kind == ONIG_ENC_KIND_SHIFT_JIS
    return zr_onig_mbn_to_code(p, e, zr_onig_mb_precise_len(enc, p, e))
  end
  return zr_onig_cesu8_to_code(enc, p, e) if kind == ONIG_ENC_KIND_CESU8
  b0 = Machine.word(Machine.load8(p, 0))
  if kind == ONIG_ENC_KIND_UTF16LE
    b1 = Machine.word(Machine.load8(p, 1))
    if (b1 & 252) == 216
      return (((b1 << 8) + b0) & 1023) * 1024 + (((Machine.word(Machine.load8(p, 3)) << 8) + Machine.word(Machine.load8(p, 2))) & 1023) + 65536
    end
    return (b1 * 256) + b0
  end
  if kind == ONIG_ENC_KIND_UTF16BE
    b1 = Machine.word(Machine.load8(p, 1))
    if (b0 & 252) == 216
      return (((b0 << 8) + b1) & 1023) * 1024 + (((Machine.word(Machine.load8(p, 2)) << 8) + Machine.word(Machine.load8(p, 3))) & 1023) + 65536
    end
    return (b0 * 256) + b1
  end
  if kind == ONIG_ENC_KIND_UTF32LE
    return Machine.word(Machine.load32(p, 0))
  end
  if kind == ONIG_ENC_KIND_UTF32BE
    return (b0 << 24) | (Machine.word(Machine.load8(p, 1)) << 16) | (Machine.word(Machine.load8(p, 2)) << 8) | Machine.word(Machine.load8(p, 3))
  end
  zr_onig_mbn_to_code(p, e, zr_onig_enclen(enc, p, e))
end

# code_to_mbc of the Unicode encodings into buf; the bytes written.
sig [Word, Word, Ptr] => Word
machine def zr_onig_code_to_mbc(enc, code, buf)
  kind = zr_onig_enc_kind(enc)
  if kind == ONIG_ENC_KIND_UTF16LE || kind == ONIG_ENC_KIND_UTF16BE
    if code > 65535
      high = (code >> 10) + 55232
      low = (code & 1023) + 56320
      zr_onig_store16(buf, high, kind == ONIG_ENC_KIND_UTF16BE)
      zr_onig_store16(buf + 2, low, kind == ONIG_ENC_KIND_UTF16BE)
      return 4
    end
    zr_onig_store16(buf, code, kind == ONIG_ENC_KIND_UTF16BE)
    return 2
  end
  if kind == ONIG_ENC_KIND_UTF32LE
    Machine.store32(buf, 0, Machine.i32(code))
    return 4
  end
  if kind == ONIG_ENC_KIND_UTF32BE
    Machine.store8(buf, 0, Machine.i8(code >> 24))
    Machine.store8(buf, 1, Machine.i8(code >> 16))
    Machine.store8(buf, 2, Machine.i8(code >> 8))
    Machine.store8(buf, 3, Machine.i8(code))
    return 4
  end
  if code < 128
    Machine.store8(buf, 0, Machine.i8(code))
    return 1
  end
  if code < 2048
    Machine.store8(buf, 0, Machine.i8(((code >> 6) & 31) | 192))
    Machine.store8(buf, 1, Machine.i8((code & 63) | 128))
    return 2
  end
  if code < 65536 || kind == ONIG_ENC_KIND_CESU8
    if code >= 65536
      high = (code >> 10) + 55232
      zr_onig_store_utf8_3(buf, high)
      zr_onig_store_utf8_3(buf + 3, (code & 1023) + 56320)
      return 6
    end
    zr_onig_store_utf8_3(buf, code)
    return 3
  end
  Machine.store8(buf, 0, Machine.i8(((code >> 18) & 7) | 240))
  Machine.store8(buf, 1, Machine.i8(((code >> 12) & 63) | 128))
  Machine.store8(buf, 2, Machine.i8(((code >> 6) & 63) | 128))
  Machine.store8(buf, 3, Machine.i8((code & 63) | 128))
  4
end

sig [Ptr, Word, Bool] => Void
machine def zr_onig_store16(buf, v, big)
  if big
    Machine.store8(buf, 0, Machine.i8(v >> 8))
    Machine.store8(buf, 1, Machine.i8(v))
  else
    Machine.store8(buf, 0, Machine.i8(v))
    Machine.store8(buf, 1, Machine.i8(v >> 8))
  end
end

sig [Ptr, Word] => Void
machine def zr_onig_store_utf8_3(buf, code)
  Machine.store8(buf, 0, Machine.i8(((code >> 12) & 15) | 224))
  Machine.store8(buf, 1, Machine.i8(((code >> 6) & 63) | 128))
  Machine.store8(buf, 2, Machine.i8((code & 63) | 128))
end

# The tail every left_adjust_char_head of the EUC and trail-byte
# encodings shares: from the head q found, the character there if it
# holds s, else the even offset past it.
sig [Ptr, Ptr, Word] => Ptr
machine def zr_onig_adjust_tail(s, q, len)
  return q if q + len > s
  q = q + len
  q + (Machine.word(s - q) & (0 - 2))
end

# left_adjust_char_head of euc_jp.c, euc_kr.c and euc_tw.c: back over
# the bytes no character starts with.
sig [Word, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_euc_left_adjust(enc, start, s, e)
  p = s
  while ((Machine.word(Machine.load8(p, 0)) - 161) & 255) <= 93 && p > start
    p = p - 1
  end
  if zr_onig_enc_kind(enc) == ONIG_ENC_KIND_EUC_JP
    return zr_onig_adjust_tail(s, p, zr_onig_mb_precise_len(enc, p, e))
  end
  zr_onig_adjust_tail(s, p, zr_onig_enclen(enc, p, e))
end

# left_adjust_char_head of shift_jis.h, big5.c, gbk.c and cp949.c: back
# over the lead bytes before a byte that can trail.
sig [Word, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_trail_left_adjust(enc, start, s, e)
  p = s
  if zr_onig_enc_byte(enc, 40, Machine.word(Machine.load8(p, 0))) != 0
    while p > start
      p = p - 1
      if zr_onig_enc_byte(enc, 32, Machine.word(Machine.load8(p, 0))) <= 1
        p = p + 1
        break
      end
    end
  end
  if zr_onig_enc_kind(enc) == ONIG_ENC_KIND_SHIFT_JIS
    return zr_onig_adjust_tail(s, p, zr_onig_mb_precise_len(enc, p, e))
  end
  zr_onig_adjust_tail(s, p, zr_onig_enclen(enc, p, e))
end

# gb18030_left_adjust_char_head: a state machine over the byte classes
# of GB18030_MAP (C1 0, C2 1, C4 2, CM 3) read backward from s. Each
# state's move is 23 * 4 cells of zr_onig_gb18030_moves: a state to go
# to, or 100 + n to answer n bytes before s.
sig [Word, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_gb18030_left_adjust(enc, start, s, e)
  moves = zr_onig_gb18030_moves()
  state = 0
  p = s
  while p >= start
    cls = zr_onig_enc_byte(enc, 72, Machine.word(Machine.load8(p, 0)))
    move = Machine.word(Machine.load8(moves + (state * 4) + cls, 0))
    return s - (move - 100) if move >= 100
    state = move
    break if p == start
    p = p - 1
  end
  s - Machine.word(Machine.load8(moves + 92 + state, 0))
end

# The moves of gb18030_left_adjust_char_head, then what each state
# answers when the text runs out.
sig [] => Ptr
machine def zr_onig_gb18030_moves
  Machine.bytes(
  "\x64\x01\x02\x03\x64\x64\x64\x04\x64\x64\x64\x06\x64\x64\x0f\x04\x65\x65\x65\x05\x64\x64\x64\x04\x65\x65\x08\x05\x65\x65\x08\x0b\
\x65\x65\x65\x09\x67\x67\x0a\x0d\x67\x67\x67\x07\x67\x67\x67\x0c\x65\x65\x65\x0b\x65\x65\x65\x0e\x67\x67\x67\x0d\x64\x64\x64\x10\
\x66\x66\x11\x13\x66\x66\x66\x12\x64\x64\x0f\x15\x64\x64\x64\x14\x66\x66\x66\x13\x66\x66\x66\x16\x64\x64\x64\x15\x00\x00\x00\x00\
\x01\x00\x01\x01\x01\x03\x03\x03\x01\x01\x03\x00\x02\x02\x00\x00\x02\x02\x00")
end

# ONIGENC_LEFT_ADJUST_CHAR_HEAD: the head of the character holding s.
sig [Word, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_left_adjust(enc, start, s, e)
  kind = zr_onig_enc_kind(enc)
  return s if kind == ONIG_ENC_KIND_SINGLE_BYTE
  return zr_onig_gb18030_left_adjust(enc, start, s, e) if kind == ONIG_ENC_KIND_GB18030
  return s if s <= start
  if kind == ONIG_ENC_KIND_UTF8 || kind == ONIG_ENC_KIND_CESU8
    p = s
    while (Machine.word(Machine.load8(p, 0)) & 192) == 128 && p > start
      p = p - 1
    end
    if kind == ONIG_ENC_KIND_CESU8 && p > start && Machine.word(s - p) == 2 && (zr_onig_decode3(p) >> 10) == 55
      pair = p - 1
      while (Machine.word(Machine.load8(pair, 0)) & 192) == 128 && pair > start
        pair = pair - 1
      end
      return pair if Machine.word(p - pair) == 3 && (zr_onig_decode3(pair) >> 10) == 54
    end
    return p
  end
  if kind == ONIG_ENC_KIND_EUC_JP || kind == ONIG_ENC_KIND_EUC_KR || kind == ONIG_ENC_KIND_EUC_TW
    return zr_onig_euc_left_adjust(enc, start, s, e)
  end
  if kind == ONIG_ENC_KIND_SHIFT_JIS || kind == ONIG_ENC_KIND_TRAIL
    return zr_onig_trail_left_adjust(enc, start, s, e)
  end
  if kind == ONIG_ENC_KIND_EMACS_MULE
    p = s
    while Machine.word(Machine.load8(p, 0)) >= 158 && p > start
      p = p - 1
    end
    return p
  end
  if kind == ONIG_ENC_KIND_UTF16LE || kind == ONIG_ENC_KIND_UTF16BE
    p = s
    p = p - 1 if (Machine.word(p - start) & 1) == 1
    at = kind == ONIG_ENC_KIND_UTF16LE ? 1 : 0
    if (Machine.word(Machine.load8(p + at, 0)) & 252) == 220 && p > start + 1
      p = p - 2
    end
    return p
  end
  s - (Machine.word(s - start) % 4)
end

# onigenc_get_right_adjust_char_head.
sig [Word, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_right_adjust(enc, start, s, e)
  p = zr_onig_left_adjust(enc, start, s, e)
  if p < s
    p = p + zr_onig_enclen(enc, p, e)
  end
  p
end

# onigenc_get_prev_char_head: the character before s, or 0 at the start.
sig [Word, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_prev_char_head(enc, start, s, e)
  return Machine.ptr(0) if s <= start
  zr_onig_left_adjust(enc, start, s - 1, e)
end

# onigenc_step_back: n characters back from s, or 0 past the start.
sig [Word, Ptr, Ptr, Ptr, Word] => Ptr
machine def zr_onig_step_back(enc, start, s, e, n)
  while s != 0 && n > 0
    n -= 1
    return Machine.ptr(0) if s <= start
    s = zr_onig_left_adjust(enc, start, s - 1, e)
  end
  s
end

# ONIGENC_IS_MBC_NEWLINE: a 0x0a at p, inside the text, as a character
# of the encoding. Under ruby no option makes CRLF a terminator, so
# is_mbc_newline_ex is this.
sig [Word, Ptr, Ptr] => Bool
machine def zr_onig_newline_p(enc, p, e)
  kind = zr_onig_enc_kind(enc)
  if kind < ONIG_ENC_KIND_UTF16LE
    return p < e && Machine.load8(p, 0) == Machine.i8(10)
  end
  if kind == ONIG_ENC_KIND_UTF16LE || kind == ONIG_ENC_KIND_UTF16BE
    return false if p + 1 >= e
    at = kind == ONIG_ENC_KIND_UTF16LE ? 0 : 1
    return Machine.word(Machine.load8(p + at, 0)) == 10 && Machine.word(Machine.load8(p + (1 - at), 0)) == 0
  end
  return false if p + 3 >= e
  zr_onig_mbc_to_code(enc, p, e) == 10
end

# onig_is_in_code_range over `ranges`: a u32 count then (low, high)
# u32 pairs, as the CCLASS_MB operand and the CR_Word table are laid out.
sig [Ptr, Word] => Bool
machine def zr_onig_in_code_range_p(ranges, code)
  n = Machine.word(Machine.load32(ranges, 0))
  data = ranges + 4
  low = 0
  high = n
  while low < high
    x = (low + high) >> 1
    if code > Machine.word(Machine.load32(data + (x * 8), 4))
      low = x + 1
    else
      high = x
    end
  end
  low < n && code >= Machine.word(Machine.load32(data + (low * 8), 0))
end

# ONIGENC_IS_ASCII_CODE_CTYPE(code, WORD)
sig [Word] => Bool
machine def zr_onig_ascii_word_p(code)
  return false if code >= 128
  (Machine.word(Machine.load32(zr_onig_ctype_bits() + (code * 4), 0)) & ONIG_CTYPE_WORD_BIT) != 0
end

# The code_to_mbclen of each multibyte encoding past Unicode, as far as
# is_code_ctype asks it: whether the code is of more than a byte.
sig [Word, Word] => Bool
machine def zr_onig_wide_code_p(enc, code)
  kind = zr_onig_enc_kind(enc)
  return code > 255 && code <= 65535 if kind == ONIG_ENC_KIND_TRAIL || kind == ONIG_ENC_KIND_EUC_KR
  return (code & 4294967040) != 0 if kind == ONIG_ENC_KIND_EUC_TW || kind == ONIG_ENC_KIND_GB18030
  if kind == ONIG_ENC_KIND_EUC_JP
    return false if code > 16777215
    return true if (code & 4286611584) == 8421504
    return (code & 4294934656) == 32896
  end
  return true if kind == ONIG_ENC_KIND_SHIFT_JIS
  (code & 4278190080) >= 2147483648 || (code & 16711680) >= 8388608 || (code & 65280) >= 32768
end

# ONIGENC_IS_CODE_WORD: each encoding's is_code_ctype(code, WORD).
sig [Word, Word] => Bool
machine def zr_onig_code_word_p(enc, code)
  kind = zr_onig_enc_kind(enc)
  if kind == ONIG_ENC_KIND_SINGLE_BYTE
    return false if code >= 256
    return zr_onig_enc_byte(enc, 56, code) != 0
  end
  if kind == ONIG_ENC_KIND_UTF8 || kind == ONIG_ENC_KIND_CESU8 || kind >= ONIG_ENC_KIND_UTF16LE
    if code < 256
      return (Machine.word(Machine.load32(zr_onig_ctype_bits() + (code * 4), 0)) & ONIG_CTYPE_WORD_BIT) != 0
    end
    return zr_onig_in_code_range_p(zr_onig_word_ranges(), code)
  end
  return zr_onig_ascii_word_p(code) if code < 128
  zr_onig_wide_code_p(enc, code)
end

# ONIGENC_IS_MBC_WORD.
sig [Word, Ptr, Ptr] => Bool
machine def zr_onig_mbc_word_p(enc, s, e)
  zr_onig_code_word_p(enc, zr_onig_mbc_to_code(enc, s, e))
end

# ONIGENC_IS_MBC_ASCII_WORD: onigenc_ascii_is_code_ctype(code, WORD).
sig [Word, Ptr, Ptr] => Bool
machine def zr_onig_mbc_ascii_word_p(enc, s, e)
  zr_onig_ascii_word_p(zr_onig_mbc_to_code(enc, s, e))
end

# ONIGENC_ASCII_CODE_TO_LOWER_CASE.
sig [Word] => Word
machine def zr_onig_ascii_lower(c)
  (c >= 65 && c <= 90) ? c + 32 : c
end

# The fold row of `code` in zr_onig_fold_rows (rows of from, n, c0, c1,
# c2 as u32, sorted by from), or 0 for none: onigenc_unicode_fold_lookup.
sig [Word] => Ptr
machine def zr_onig_fold_lookup(code)
  table = zr_onig_fold_rows()
  n = Machine.word(Machine.load32(table, 0))
  rows = table + 4
  low = 0
  high = n
  while low < high
    x = (low + high) >> 1
    row = rows + (x * 20)
    from = Machine.word(Machine.load32(row, 0))
    if from == code
      return row
    end
    if from < code
      low = x + 1
    else
      high = x
    end
  end
  Machine.ptr(0)
end

# onigenc_unicode_mbc_case_fold: the character at p folded into `fold`;
# the folded byte length. The caller moves past the character.
sig [Word, Ptr, Ptr, Ptr] => Word
machine def zr_onig_unicode_case_fold(enc, p, e, fold)
  code = zr_onig_mbc_to_code(enc, p, e)
  len = zr_onig_enclen(enc, p, e)
  row = zr_onig_fold_lookup(code)
  if row != 0
    n = Machine.word(Machine.load32(row, 4))
    rlen = 0
    i = 0
    while i < n
      rlen += zr_onig_code_to_mbc(enc, Machine.word(Machine.load32(row + (i * 4), 8)), fold + rlen)
      i += 1
    end
    return rlen
  end
  i = 0
  while i < len
    Machine.store8(fold + i, 0, Machine.load8(p + i, 0))
    i += 1
  end
  len
end

# get_lower_case of euc_jp.c and shift_jis.h.
sig [Word, Word] => Word
machine def zr_onig_jis_lower(kind, code)
  if kind == ONIG_ENC_KIND_EUC_JP
    return code + 32 if code >= 41921 && code <= 41946
    return code + 32 if code >= 42657 && code <= 42680
    return code + 48 if code >= 42913 && code <= 42945
    return code
  end
  return code + 33 if code >= 33376 && code <= 33401
  return code + 32 if code >= 33695 && code <= 33718
  if code >= 33856 && code <= 33888
    return code + 49 if code >= 33871
    return code + 48
  end
  code
end

# mbc_case_fold of euc_jp.c and shift_jis.h, past ASCII: the lower-case
# code's bytes. EUC-JP reads bytes that are not a character as their
# first. The answer is the byte length written, which is also how far
# the text moves.
sig [Word, Ptr, Ptr, Ptr] => Word
machine def zr_onig_jis_case_fold(enc, p, e, fold)
  kind = zr_onig_enc_kind(enc)
  code = zr_onig_jis_lower(kind, zr_onig_mbc_to_code(enc, p, e))
  len = 0
  if (code & 16711680) != 0
    Machine.store8(fold + len, 0, Machine.i8(code >> 16))
    len += 1
  end
  if (code & 65280) != 0
    Machine.store8(fold + len, 0, Machine.i8(code >> 8))
    len += 1
  end
  Machine.store8(fold + len, 0, Machine.i8(code))
  len += 1
  if kind == ONIG_ENC_KIND_EUC_JP && zr_onig_mb_precise_len(enc, fold, fold + len) != len
    return 1
  end
  len
end

# ONIGENC_MBC_CASE_FOLD: the character at the pointer in the cell `pp`
# folded under `flag` into `fold` (ONIG_MBC_CASE_FOLD_MAXLEN bytes), the
# cell moved past it; the folded byte length.
sig [Word, Word, Ptr, Ptr, Ptr] => Word
machine def zr_onig_mbc_case_fold(enc, flag, pp, e, fold)
  p = Machine.ptr(Machine.load64(pp, 0))
  kind = zr_onig_enc_kind(enc)
  c = Machine.word(Machine.load8(p, 0))
  if kind == ONIG_ENC_KIND_SINGLE_BYTE
    Machine.store64(pp, 0, Machine.word(p + 1))
    if c == 223 && (OnigEnc.flags(Machine.ptr(enc)) & ONIG_ENC_FLAG_SHARP_S) != 0 && (flag & ONIG_CASE_FOLD_MULTI_CHAR) != 0
      Machine.store8(fold, 0, Machine.i8(115))
      Machine.store8(fold, 1, Machine.i8(115))
      return 2
    end
    Machine.store8(fold, 0, Machine.i8(zr_onig_enc_byte(enc, 48, c)))
    return 1
  end
  if kind >= ONIG_ENC_KIND_UTF16LE
    width = kind >= ONIG_ENC_KIND_UTF32LE ? 4 : 2
    code = zr_onig_mbc_to_code(enc, p, e)
    if code < 128
      Machine.store64(pp, 0, Machine.word(p + width))
      return zr_onig_code_to_mbc(enc, zr_onig_ascii_lower(code), fold)
    end
    Machine.store64(pp, 0, Machine.word(p + zr_onig_enclen(enc, p, e)))
    return zr_onig_unicode_case_fold(enc, p, e, fold)
  end
  if c < 128
    Machine.store8(fold, 0, Machine.i8(zr_onig_ascii_lower(c)))
    Machine.store64(pp, 0, Machine.word(p + 1))
    return 1
  end
  if kind == ONIG_ENC_KIND_UTF8 || kind == ONIG_ENC_KIND_CESU8
    Machine.store64(pp, 0, Machine.word(p + zr_onig_enclen(enc, p, e)))
    return zr_onig_unicode_case_fold(enc, p, e, fold)
  end
  if kind == ONIG_ENC_KIND_EUC_JP || kind == ONIG_ENC_KIND_SHIFT_JIS
    len = zr_onig_jis_case_fold(enc, p, e, fold)
    Machine.store64(pp, 0, Machine.word(p + len))
    return len
  end
  len = kind == ONIG_ENC_KIND_EMACS_MULE ? zr_onig_mb_precise_len(enc, p, e) : zr_onig_enclen(enc, p, e)
  i = 0
  while i < len
    Machine.store8(fold + i, 0, Machine.load8(p + i, 0))
    i += 1
  end
  Machine.store64(pp, 0, Machine.word(p + len))
  len
end

# string_cmp_ic (regexec.c): whether the `mblen` bytes at s1 and the
# text at s2 fold the same; the text pointer past the compared part, or
# 0 when they differ.
sig [Word, Word, Ptr, Ptr, Word, Ptr] => Ptr
machine def zr_onig_string_cmp_ic(enc, flag, s1, s2, mblen, text_end)
  buf1 = Machine.slot(ONIG_MBC_CASE_FOLD_MAXLEN)
  buf2 = Machine.slot(ONIG_MBC_CASE_FOLD_MAXLEN)
  cell1 = Machine.slot(8)
  cell2 = Machine.slot(8)
  Machine.store64(cell1, 0, Machine.word(s1))
  Machine.store64(cell2, 0, Machine.word(s2))
  end1 = s1 + mblen
  while Machine.ptr(Machine.load64(cell1, 0)) < end1
    len1 = zr_onig_mbc_case_fold(enc, flag, cell1, text_end, buf1)
    len2 = zr_onig_mbc_case_fold(enc, flag, cell2, text_end, buf2)
    return Machine.ptr(0) if len1 != len2
    i = 0
    while i < len1
      return Machine.ptr(0) if Machine.load8(buf1 + i, 0) != Machine.load8(buf2 + i, 0)
      i += 1
    end
  end
  Machine.ptr(Machine.load64(cell2, 0))
end

# str_lower_case_match (regexec.c): whether the folded text at p (up to
# end) starts with the already-folded bytes t..tend.
sig [Word, Word, Ptr, Ptr, Ptr, Ptr] => Bool
machine def zr_onig_str_lower_case_match(enc, flag, t, tend, p, e)
  lowbuf = Machine.slot(ONIG_MBC_CASE_FOLD_MAXLEN)
  cell = Machine.slot(8)
  Machine.store64(cell, 0, Machine.word(p))
  while t < tend
    lowlen = zr_onig_mbc_case_fold(enc, flag, cell, e, lowbuf)
    q = lowbuf
    while lowlen > 0
      return false if Machine.load8(t, 0) != Machine.load8(q, 0)
      t = t + 1
      q = q + 1
      lowlen -= 1
    end
  end
  true
end
