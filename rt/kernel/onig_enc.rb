# The two encodings Onigmo's matcher reads under ze0: UTF-8 (enc/utf_8.c)
# and bytewise ASCII (enc/ascii.c), with the helpers of regenc.c and
# enc/unicode.c the matcher calls. `enc` is ONIG_ENC_ASCII or
# ONIG_ENC_UTF8. Derived from Onigmo; the license is in rt/kernel/regexp.rb.
ONIG_ENC_ASCII = 0
ONIG_ENC_UTF8 = 1
ONIG_CTYPE_WORD_BIT = 4096
ONIG_MBC_CASE_FOLD_MAXLEN = 18

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

# enclen: onigenc_mbclen (regenc.c), the length clipped to the text.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_enclen(enc, p, e)
  return 1 if enc == ONIG_ENC_ASCII
  r = zr_onig_utf8_precise_len(p, e)
  if r > 0
    return Machine.word(e - p) if p + r > e
    return r
  end
  return Machine.word(e - p) if r < 0 - 1
  p < e ? 1 : 0
end

# enclen_approx (regexec.c): onigenc_mbclen_approximate for UTF-8, the
# bytes a truncated character would have had.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_enclen_approx(enc, p, e)
  if enc == ONIG_ENC_ASCII
    return p < e ? 1 : 0
  end
  r = zr_onig_utf8_precise_len(p, e)
  return r if r > 0
  return Machine.word(e - p) + (0 - 1 - r) if r < 0 - 1
  1
end

# ONIGENC_IS_MBC_HEAD: whether the character at p is longer than a byte.
sig [Word, Ptr, Ptr] => Bool
machine def zr_onig_mbc_head_p(enc, p, e)
  zr_onig_enclen(enc, p, e) != 1
end

# ONIGENC_MBC_TO_CODE: utf_8.c's mbc_to_code, the first byte for
# anything that is not a whole character.
sig [Word, Ptr, Ptr] => Word
machine def zr_onig_mbc_to_code(enc, p, e)
  c = Machine.word(Machine.load8(p, 0))
  return c if enc == ONIG_ENC_ASCII
  len = zr_onig_utf8_precise_len(p, e)
  return c if len <= 1
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

# code_to_mbc (utf_8.c) into buf; the bytes written.
sig [Word, Word, Ptr] => Word
machine def zr_onig_code_to_mbc(enc, code, buf)
  if enc == ONIG_ENC_ASCII || code < 128
    Machine.store8(buf, 0, Machine.i8(code))
    return 1
  end
  if code < 2048
    Machine.store8(buf, 0, Machine.i8(((code >> 6) & 31) | 192))
    Machine.store8(buf, 1, Machine.i8((code & 63) | 128))
    return 2
  end
  if code < 65536
    Machine.store8(buf, 0, Machine.i8(((code >> 12) & 15) | 224))
    Machine.store8(buf, 1, Machine.i8(((code >> 6) & 63) | 128))
    Machine.store8(buf, 2, Machine.i8((code & 63) | 128))
    return 3
  end
  Machine.store8(buf, 0, Machine.i8(((code >> 18) & 7) | 240))
  Machine.store8(buf, 1, Machine.i8(((code >> 12) & 63) | 128))
  Machine.store8(buf, 2, Machine.i8(((code >> 6) & 63) | 128))
  Machine.store8(buf, 3, Machine.i8((code & 63) | 128))
  4
end

# ONIGENC_LEFT_ADJUST_CHAR_HEAD: the head of the character holding s.
sig [Word, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_left_adjust(enc, start, s, e)
  return s if enc == ONIG_ENC_ASCII
  return s if s <= start
  p = s
  while (Machine.word(Machine.load8(p, 0)) & 192) == 128 && p > start
    p = p - 1
  end
  p
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

# ONIGENC_IS_MBC_NEWLINE: a 0x0a at p, inside the text. Under ruby no
# option makes CRLF a terminator, so is_mbc_newline_ex is this.
sig [Ptr, Ptr] => Bool
machine def zr_onig_newline_p(p, e)
  p < e && Machine.load8(p, 0) == Machine.i8(10)
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

# ONIGENC_IS_CODE_WORD: onigenc_unicode_is_code_ctype for UTF-8 (the
# Latin-1 bits under 256, CR_Word above), the ASCII table for ASCII.
sig [Word, Word] => Bool
machine def zr_onig_code_word_p(enc, code)
  if code < 128
    return (Machine.word(Machine.load32(zr_onig_ctype_bits() + (code * 4), 0)) & ONIG_CTYPE_WORD_BIT) != 0
  end
  return false if enc == ONIG_ENC_ASCII
  if code < 256
    return (Machine.word(Machine.load32(zr_onig_ctype_bits() + (code * 4), 0)) & ONIG_CTYPE_WORD_BIT) != 0
  end
  zr_onig_in_code_range_p(zr_onig_word_ranges(), code)
end

# ONIGENC_IS_MBC_WORD.
sig [Word, Ptr, Ptr] => Bool
machine def zr_onig_mbc_word_p(enc, s, e)
  zr_onig_code_word_p(enc, zr_onig_mbc_to_code(enc, s, e))
end

# ONIGENC_IS_MBC_ASCII_WORD: onigenc_ascii_is_code_ctype(code, WORD).
sig [Word, Ptr, Ptr] => Bool
machine def zr_onig_mbc_ascii_word_p(enc, s, e)
  code = zr_onig_mbc_to_code(enc, s, e)
  return false if code >= 128
  (Machine.word(Machine.load32(zr_onig_ctype_bits() + (code * 4), 0)) & ONIG_CTYPE_WORD_BIT) != 0
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

# ONIGENC_MBC_CASE_FOLD: the character at the pointer in the cell `pp`
# folded into `fold` (ONIG_MBC_CASE_FOLD_MAXLEN bytes), the cell moved
# past it; the folded byte length. utf_8.c's mbc_case_fold for UTF-8,
# onigenc_ascii_mbc_case_fold for ASCII.
sig [Word, Ptr, Ptr, Ptr] => Word
machine def zr_onig_mbc_case_fold(enc, pp, e, fold)
  p = Machine.ptr(Machine.load64(pp, 0))
  c = Machine.word(Machine.load8(p, 0))
  if enc == ONIG_ENC_ASCII || c < 128
    Machine.store8(fold, 0, Machine.i8(zr_onig_ascii_lower(c)))
    Machine.store64(pp, 0, Machine.word(p + 1))
    return 1
  end
  code = zr_onig_mbc_to_code(enc, p, e)
  len = zr_onig_enclen(enc, p, e)
  Machine.store64(pp, 0, Machine.word(p + len))
  row = zr_onig_fold_lookup(code)
  if row != 0
    n = Machine.word(Machine.load32(row, 4))
    if n == 1
      return zr_onig_code_to_mbc(enc, Machine.word(Machine.load32(row, 8)), fold)
    end
    rlen = 0
    i = 0
    while i < n
      k = zr_onig_code_to_mbc(enc, Machine.word(Machine.load32(row + (i * 4), 8)), fold + rlen)
      rlen += k
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

# string_cmp_ic (regexec.c): whether the `mblen` bytes at s1 and the
# text at s2 fold the same; the text pointer past the compared part, or
# 0 when they differ.
sig [Word, Ptr, Ptr, Word, Ptr] => Ptr
machine def zr_onig_string_cmp_ic(enc, s1, s2, mblen, text_end)
  buf1 = Machine.slot(ONIG_MBC_CASE_FOLD_MAXLEN)
  buf2 = Machine.slot(ONIG_MBC_CASE_FOLD_MAXLEN)
  cell1 = Machine.slot(8)
  cell2 = Machine.slot(8)
  Machine.store64(cell1, 0, Machine.word(s1))
  Machine.store64(cell2, 0, Machine.word(s2))
  end1 = s1 + mblen
  while Machine.ptr(Machine.load64(cell1, 0)) < end1
    len1 = zr_onig_mbc_case_fold(enc, cell1, text_end, buf1)
    len2 = zr_onig_mbc_case_fold(enc, cell2, text_end, buf2)
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
sig [Word, Ptr, Ptr, Ptr, Ptr] => Bool
machine def zr_onig_str_lower_case_match(enc, t, tend, p, e)
  lowbuf = Machine.slot(ONIG_MBC_CASE_FOLD_MAXLEN)
  cell = Machine.slot(8)
  Machine.store64(cell, 0, Machine.word(p))
  while t < tend
    lowlen = zr_onig_mbc_case_fold(enc, cell, e, lowbuf)
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
