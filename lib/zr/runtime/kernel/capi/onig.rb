module Zr::Kern
  # The functions of an rb_encoding (OnigEncodingType), which CRuby's
  # inline encoding functions call through the struct: rb_enc_mbcput
  # calls code_to_mbc, rb_enc_isspace is_code_ctype, rb_enc_left_char_head
  # left_adjust_char_head, and so on. Each one reads the encoding through
  # the descriptor that its struct keeps, with the primitives of zr's
  # matcher (onig_enc.rb), so C and a Regexp find the same characters.

  # ONIGENC_CTYPE_*, the classes that is_code_ctype tests. Each is a bit
  # of a code's word in the ctype table (zr_onig_ctype_bits).
  ONIGENC_CTYPE_ALPHA = 1
  ONIGENC_CTYPE_GRAPH = 5
  ONIGENC_CTYPE_PRINT = 7
  ONIGENC_CTYPE_WORD = 12
  ONIGENC_CTYPE_ALNUM = 13
  ONIGENC_CTYPE_ASCII = 14
  # The answers of the functions that zr's encodings do not support.
  ONIG_NO_SUPPORT_CONFIG = 0 - 2
  ONIGERR_INVALID_CHAR_PROPERTY_NAME = 0 - 223

  # Gives the struct `enc` of the Encoding `encoding` its descriptor, its
  # Unicode flag and its functions.
  #: (ptr, value) -> void
  def zr_capi_onig_attach(enc, encoding)
    descriptor = zr_capi_call1(zr_core_class(Machine.id(:Regexp)), Machine.id(:onig_descriptor), encoding)
    onig = Machine.word(RString[descriptor].ptr)
    RbEncoding[enc].onig = onig
    if zr_capi_onig_unicode_p(onig)
      RbEncoding[enc].flags = Machine.i32(ONIGENC_FLAG_UNICODE)
    end
    RbEncoding[enc].precise_mbc_enc_len = Machine.addr(:zr_capi_onig_precise_len)
    RbEncoding[enc].is_mbc_newline = Machine.addr(:zr_capi_onig_newline)
    RbEncoding[enc].mbc_to_code = Machine.addr(:zr_capi_onig_mbc_to_code)
    RbEncoding[enc].code_to_mbclen = Machine.addr(:zr_capi_onig_code_to_mbclen)
    RbEncoding[enc].code_to_mbc = Machine.addr(:zr_capi_onig_code_to_mbc)
    RbEncoding[enc].mbc_case_fold = Machine.addr(:zr_capi_onig_mbc_case_fold)
    RbEncoding[enc].apply_all_case_fold = Machine.addr(:zr_capi_onig_no_folds)
    RbEncoding[enc].get_case_fold_codes_by_str = Machine.addr(:zr_capi_onig_no_fold_codes)
    RbEncoding[enc].property_name_to_ctype = Machine.addr(:zr_capi_onig_property_name_to_ctype)
    RbEncoding[enc].is_code_ctype = Machine.addr(:zr_capi_onig_is_code_ctype)
    RbEncoding[enc].get_ctype_code_range = Machine.addr(:zr_capi_onig_ctype_code_range)
    RbEncoding[enc].left_adjust_char_head = Machine.addr(:zr_capi_onig_left_adjust)
    RbEncoding[enc].is_allowed_reverse_match = Machine.addr(:zr_capi_onig_reverse_match)
    RbEncoding[enc].case_map = Machine.addr(:zr_capi_onig_case_map)
  end

  # precise_mbc_enc_len: the length of the character at `p`, or CRuby's
  # code for one that needs more bytes or is invalid.
  #: (ptr, ptr, ptr) -> i32
  def zr_capi_onig_precise_len(p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_onig_precise_len(RbEncoding[enc].onig, p, e))
  end

  # is_mbc_newline: whether the character at `p` is a newline.
  #: (ptr, ptr, ptr) -> i32
  def zr_capi_onig_newline(p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_onig_newline_p(RbEncoding[enc].onig, p, e) ? Machine.i32(1) : Machine.i32(0)
  end

  # mbc_to_code: the code point of the character at `p`.
  #: (ptr, ptr, ptr) -> i32
  def zr_capi_onig_mbc_to_code(p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_onig_mbc_to_code(RbEncoding[enc].onig, p, e))
  end

  # code_to_mbc: writes the character of `code` at `buf`; its length.
  #: (i32, ptr, ptr) -> i32
  def zr_capi_onig_code_to_mbc(code, buf, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_onig_write(RbEncoding[enc].onig, Machine.u32(code), buf))
  end

  # code_to_mbclen: the length of the character of `code`.
  #: (i32, ptr) -> i32
  def zr_capi_onig_code_to_mbclen(code, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_onig_write(RbEncoding[enc].onig, Machine.u32(code), Machine.slot(8)))
  end

  # The character of `code` at `buf`, and its length: a byte of a
  # single-byte encoding, the Unicode forms of onig_enc.rb, or the code's
  # bytes, high first, of the other multibyte encodings
  # (onigenc_mb2_code_to_mbc, onigenc_mb4_code_to_mbc).
  #: (word, word, ptr) -> word
  def zr_capi_onig_write(onig, code, buf)
    if zr_onig_enc_kind(onig) == ONIG_ENC_KIND_SINGLE_BYTE
      Machine.store8(buf, 0, Machine.i8(code))
      return 1
    end
    if zr_capi_onig_unicode_p(onig)
      return zr_onig_code_to_mbc(onig, code, buf)
    end
    n = 0
    shift = 24
    while shift > 0
      byte = (code >> shift) & 255
      if byte != 0 || n > 0
        Machine.store8(buf + n, 0, Machine.i8(byte))
        n += 1
      end
      shift -= 8
    end
    Machine.store8(buf + n, 0, Machine.i8(code & 255))
    n + 1
  end

  # mbc_case_fold: writes the case fold of the character at `*pp` to `to`
  # and steps `*pp` past it; the length written.
  #: (i32, ptr, ptr, ptr, ptr) -> i32
  def zr_capi_onig_mbc_case_fold(flag, pp, e, to, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_onig_mbc_case_fold(RbEncoding[enc].onig, Machine.u32(flag), pp, e, to))
  end

  # apply_all_case_fold and get_case_fold_codes_by_str: zr's encodings
  # list no folds to C, which then folds by mbc_case_fold alone.
  #: (i32, ptr, ptr, ptr) -> i32
  def zr_capi_onig_no_folds(flag, fn, arg, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(0)
  end

  #: (i32, ptr, ptr, ptr, ptr) -> i32
  def zr_capi_onig_no_fold_codes(flag, p, e, items, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(0)
  end

  # property_name_to_ctype: C names no property that zr's encodings know.
  #: (ptr, ptr, ptr) -> i32
  def zr_capi_onig_property_name_to_ctype(enc, p, e)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(ONIGERR_INVALID_CHAR_PROPERTY_NAME)
  end

  # get_ctype_code_range: zr gives C no code ranges.
  #: (i32, ptr, ptr, ptr) -> i32
  def zr_capi_onig_ctype_code_range(ctype, sb_out, ranges, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(ONIG_NO_SUPPORT_CONFIG)
  end

  # is_code_ctype: whether `code` is of the class `ctype`.
  #: (i32, i32, ptr) -> i32
  def zr_capi_onig_is_code_ctype(code, ctype, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_onig_ctype_p(RbEncoding[enc].onig, Machine.u32(code), Machine.sword(ctype)) ? Machine.i32(1) : Machine.i32(0)
  end

  # The ctype table answers for ASCII, and for Latin-1 in a Unicode
  # encoding. Past it, a single-byte encoding knows its word bytes, and
  # the other encodings know their word characters, which answer for the
  # classes of letters (alpha, alnum, graph, print); no other class has
  # such a code.
  #: (word, word, word) -> bool
  def zr_capi_onig_ctype_p(onig, code, ctype)
    if code < 128 || (code < 256 && zr_capi_onig_unicode_p(onig))
      return (Machine.u32(Machine.load32(zr_onig_ctype_bits() + (code * 4), 0)) & (1 << ctype)) != 0
    end
    if ctype == ONIGENC_CTYPE_WORD || ctype == ONIGENC_CTYPE_ALNUM || ctype == ONIGENC_CTYPE_ALPHA ||
       ctype == ONIGENC_CTYPE_GRAPH || ctype == ONIGENC_CTYPE_PRINT
      return zr_onig_code_word_p(onig, code)
    end
    false
  end

  # left_adjust_char_head: the start of the character that `p` is in.
  #: (ptr, ptr, ptr, ptr) -> ptr
  def zr_capi_onig_left_adjust(start, p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_onig_left_adjust(RbEncoding[enc].onig, start, p, e)
  end

  # is_allowed_reverse_match: each encoding of zr's allows it.
  #: (ptr, ptr, ptr) -> i32
  def zr_capi_onig_reverse_match(p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(1)
  end

  # case_map: zr maps no case for C, which writes nothing.
  #: (ptr, ptr, ptr, ptr, ptr, ptr) -> i32
  def zr_capi_onig_case_map(flags, pp, e, to, to_end, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(0)
  end

  # --- The exported functions over them -----------------------------------

  # rb_enc_precise_mbclen: the length of the character at `p`, or how many
  # more bytes it needs (CRuby's -1 - n), or -1 for an invalid one.
  #: (ptr, ptr, ptr) -> i32
  def rb_enc_precise_mbclen(p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_precise_mbclen(p, e, enc))
  end

  #: (ptr, ptr, ptr) -> word
  def zr_capi_precise_mbclen(p, e, enc)
    if e <= p
      return 0 - 2
    end
    n = zr_onig_precise_len(RbEncoding[enc].onig, p, e)
    if n > e - p
      return 0 - 1 - (n - (e - p))
    end
    n
  end

  # rb_enc_mbclen: the length of the character at `p`; the shortest
  # character's (cut at `e`) for one that is invalid or cut short.
  #: (ptr, ptr, ptr) -> i32
  def rb_enc_mbclen(p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    n = zr_capi_precise_mbclen(p, e, enc)
    if n > 0
      return Machine.i32(n)
    end
    min = Machine.sword(RbEncoding[enc].min_enc_len)
    Machine.i32(min <= e - p ? min : e - p)
  end

  # rb_enc_ascget: the ASCII character at `p`, its length to `*len`, or
  # -1 when the character there is not ASCII.
  #: (ptr, ptr, ptr, ptr) -> i32
  def rb_enc_ascget(p, e, len, enc)
    Machine.gates_enter
    zr_c_entered()
    if e <= p
      return Machine.i32(0 - 1)
    end
    n = 1
    c = Machine.u8(Machine.load8(p, 0))
    if Machine.sword(RbEncoding[enc].min_enc_len) != 1 || zr_enc_dummy_p(zr_capi_enc_index(enc))
      n = zr_capi_precise_mbclen(p, e, enc)
      if n <= 0
        return Machine.i32(0 - 1)
      end
      c = zr_onig_mbc_to_code(RbEncoding[enc].onig, p, e)
    end
    if c >= 128
      return Machine.i32(0 - 1)
    end
    if len != 0
      Machine.store32(len, 0, Machine.i32(n))
    end
    Machine.i32(c)
  end

  # rb_enc_codelen: the length of the character of `code`.
  #: (i32, ptr) -> i32
  def rb_enc_codelen(code, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_onig_write(RbEncoding[enc].onig, Machine.u32(code), Machine.slot(8)))
  end

  # rb_enc_uint_chr: the String of the character of `code`, as
  # Integer#chr makes it, with its errors.
  #: (i32, ptr) -> value
  def rb_enc_uint_chr(code, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_capi_chr(Machine.u32(code), enc))
  end

  #: (word, ptr) -> value
  def zr_capi_chr(code, enc)
    zr_capi_call1(zr_int_from_word(code), Machine.id(:chr), zr_capi_encoding_object(zr_capi_enc_index(enc)))
  end

  # rb_enc_toupper and rb_enc_tolower: an ASCII letter in the other case;
  # any other code as it is.
  #: (i32, ptr) -> i32
  def rb_enc_toupper(c, enc)
    Machine.gates_enter
    zr_c_entered()
    code = Machine.sword(c)
    code >= 97 && code <= 122 ? Machine.i32(code - 32) : c
  end

  #: (i32, ptr) -> i32
  def rb_enc_tolower(c, enc)
    Machine.gates_enter
    zr_c_entered()
    code = Machine.sword(c)
    code >= 65 && code <= 90 ? Machine.i32(code + 32) : c
  end

  # rb_enc_unicode_p: whether `enc` is a Unicode encoding.
  #: (ptr) -> i32
  def rb_enc_unicode_p(enc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_onig_unicode_p(RbEncoding[enc].onig) ? Machine.i32(1) : Machine.i32(0)
  end

  # The functions of Onigmo's regenc.c that CRuby's inline functions call:
  # the heads of the characters around `s` within [start, e), a character
  # `n` back, a length, and a count of characters.
  #: (ptr, ptr, ptr, ptr) -> ptr
  def onigenc_get_left_adjust_char_head(enc, start, s, e)
    Machine.gates_enter
    zr_c_entered()
    zr_onig_left_adjust(RbEncoding[enc].onig, start, s, e)
  end

  #: (ptr, ptr, ptr, ptr) -> ptr
  def onigenc_get_right_adjust_char_head(enc, start, s, e)
    Machine.gates_enter
    zr_c_entered()
    zr_onig_right_adjust(RbEncoding[enc].onig, start, s, e)
  end

  #: (ptr, ptr, ptr, ptr) -> ptr
  def onigenc_get_prev_char_head(enc, start, s, e)
    Machine.gates_enter
    zr_c_entered()
    zr_onig_prev_char_head(RbEncoding[enc].onig, start, s, e)
  end

  #: (ptr, ptr, ptr, ptr, i32) -> ptr
  def onigenc_step_back(enc, start, s, e, n)
    Machine.gates_enter
    zr_c_entered()
    zr_onig_step_back(RbEncoding[enc].onig, start, s, e, Machine.sword(n))
  end

  #: (ptr, ptr, ptr) -> i32
  def onigenc_mbclen(p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_onig_mbclen(RbEncoding[enc].onig, p, e))
  end

  #: (ptr, ptr, ptr) -> i32
  def onigenc_strlen(enc, p, e)
    Machine.gates_enter
    zr_c_entered()
    onig = RbEncoding[enc].onig
    n = 0
    at = p
    while at < e
      at += zr_onig_mbclen(onig, at, e)
      n += 1
    end
    Machine.i32(n)
  end

  # Whether the descriptor reads a Unicode encoding.
  #: (word) -> bool
  def zr_capi_onig_unicode_p(onig)
    kind = zr_onig_enc_kind(onig)
    kind == ONIG_ENC_KIND_UTF8 || kind == ONIG_ENC_KIND_CESU8 || kind >= ONIG_ENC_KIND_UTF16LE
  end

  # rb_enc_nth: the `nth` character of the text [p, e), or `e` past it.
  #: (ptr, ptr, word, ptr) -> ptr
  def rb_enc_nth(p, e, nth, enc)
    Machine.gates_enter
    zr_c_entered()
    at = p
    left = nth
    onig = RbEncoding[enc].onig
    while left > 0 && at < e
      at += zr_onig_mbclen(onig, at, e)
      left -= 1
    end
    at > e ? e : at
  end
end
