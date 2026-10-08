module Zr::Kern
  # The C API's Strings. An extension reads a String's length and bytes
  # inline (RSTRING_LEN, RSTRING_PTR); these make Strings and change them.

  # A new String of the `len` bytes at `bytes` in the encoding `index`. A
  # null `bytes` gives `len` zero bytes, which C then fills, as
  # rb_str_new(NULL, len) does.
  #: (ptr, word, word) -> value
  def zr_capi_str(bytes, len, index)
    s = Machine.value(QNIL)
    if bytes == 0
      s = zr_str_new(Machine.bytes(""), 0)
      zr_str_reserve(s, len)
      Libc.memset(RString[s].ptr, Machine.i32(0), len + 1)
      RString[s].len = len
    else
      s = zr_str_new(bytes, len)
    end
    zr_str_set_index(s, index)
  end

  # rb_str_new: a binary String (ASCII-8BIT) of `len` bytes.
  #: (ptr, word) -> value
  def rb_str_new(bytes, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(bytes, len, ENC_BINARY)
  end

  # rb_str_new_static: rb_str_new for a C literal; the rb_str_new macro
  # calls it for one.
  #: (ptr, word) -> value
  def rb_str_new_static(bytes, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(bytes, len, ENC_BINARY)
  end

  #: (ptr) -> value
  def rb_str_new_cstr(text)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(text, zr_cstr_len(text), ENC_BINARY)
  end

  # rb_utf8_str_new and its forms: the same bytes, in UTF-8.
  #: (ptr, word) -> value
  def rb_utf8_str_new(bytes, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(bytes, len, ENC_UTF8)
  end

  #: (ptr, word) -> value
  def rb_utf8_str_new_static(bytes, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(bytes, len, ENC_UTF8)
  end

  #: (ptr) -> value
  def rb_utf8_str_new_cstr(text)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(text, zr_cstr_len(text), ENC_UTF8)
  end

  # rb_usascii_str_new and its forms: in US-ASCII.
  #: (ptr, word) -> value
  def rb_usascii_str_new(bytes, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(bytes, len, ENC_USASCII)
  end

  #: (ptr, word) -> value
  def rb_usascii_str_new_static(bytes, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(bytes, len, ENC_USASCII)
  end

  #: (ptr) -> value
  def rb_usascii_str_new_cstr(text)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(text, zr_cstr_len(text), ENC_USASCII)
  end

  # rb_str_buf_new: an empty binary String with room for `capa` bytes.
  #: (word) -> value
  def rb_str_buf_new(capa)
    Machine.gates_enter
    zr_c_entered()
    s = zr_capi_str(Machine.bytes(""), 0, ENC_BINARY)
    zr_str_reserve(s, capa)
    s
  end

  # rb_str_cat: appends `len` bytes to `str`, whatever their encoding.
  #: (value, ptr, word) -> value
  def rb_str_cat(str, bytes, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str_cat(str, bytes, len)
  end

  #: (value, ptr) -> value
  def rb_str_cat_cstr(str, text)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str_cat(str, text, zr_cstr_len(text))
  end

  #: (value, ptr, word) -> value
  def zr_capi_str_cat(str, bytes, len)
    zr_capi_str_modify(str)
    n = RString[str].len + len
    zr_str_reserve(str, n)
    zr_memcpy(RString[str].ptr + RString[str].len, bytes, len)
    RString[str].len = n
    Machine.store8(RString[str].ptr + n, 0, Machine.i8(0))
    zr_str_modified(str)
    str
  end

  # rb_str_modify: raises FrozenError if `str` is frozen. C writes the
  # bytes after it, so the String's scan results go.
  #: (value) -> void
  def rb_str_modify(str)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str_modify(str)
  end

  #: (value) -> void
  def zr_capi_str_modify(str)
    if zr_modify_frozen_p(str)
      zr_c_result(zr_frozen_error(str))
    end
    zr_str_modified(str)
  end

  # rb_str_resize: sets the length of `str` to `len`, keeping its first
  # bytes and NUL-ending it.
  #: (value, word) -> value
  def rb_str_resize(str, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str_modify(str)
    if len > RString[str].len
      zr_str_reserve(str, len)
      Libc.memset(RString[str].ptr + RString[str].len, Machine.i32(0), len - RString[str].len)
    end
    RString[str].len = len
    Machine.store8(RString[str].ptr + len, 0, Machine.i8(0))
    str
  end

  # rb_str_set_len: the length after C wrote the bytes, within the room
  # the String has.
  #: (value, word) -> void
  def rb_str_set_len(str, len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str_modify(str)
    RString[str].len = len
    Machine.store8(RString[str].ptr + len, 0, Machine.i8(0))
  end

  # rb_string_value (StringValue): the String at `*at`, or the String that
  # its to_str gives, which it also stores at `at`.
  #: (ptr) -> value
  def rb_string_value(at)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_string_at(at)
  end

  # rb_string_value_ptr (StringValuePtr): the bytes of that String.
  #: (ptr) -> ptr
  def rb_string_value_ptr(at)
    Machine.gates_enter
    zr_c_entered()
    RString[zr_capi_string_at(at)].ptr
  end

  # rb_string_value_cstr (StringValueCStr): the bytes, which are a C
  # string: ArgumentError if they hold a NUL.
  #: (ptr) -> ptr
  def rb_string_value_cstr(at)
    Machine.gates_enter
    zr_c_entered()
    s = zr_capi_string_at(at)
    if Libc.memchr(RString[s].ptr, Machine.i32(0), RString[s].len) != 0
      zr_c_raise(zr_global(G_ARGUMENT_ERROR), Machine.bytes("string contains null byte"), 25)
    end
    RString[s].ptr
  end

  #: (ptr) -> value
  def zr_capi_string_at(at)
    s = zr_c_result(zr_str_operand(Machine.value(Machine.load64(at, 0))))
    Machine.store64(at, 0, Machine.word(s))
    s
  end

  # rb_check_string_type: `v` as a String through to_str, or nil.
  #: (value) -> value
  def rb_check_string_type(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_global(G_STRING), Machine.id(:try_convert), v)
  end

  # rb_str_dup: a new String of `str`'s class with its bytes and
  # encoding, which does not call initialize_copy.
  #: (value) -> value
  def rb_str_dup(str)
    Machine.gates_enter
    zr_c_entered()
    copy = zr_str_copy_encoding(zr_str_new(RString[str].ptr, RString[str].len), str)
    RBasic[copy].klass = zr_real_class(str)
    copy
  end

  # rb_str_replace: replaces `str`'s bytes and encoding with `other`'s.
  #: (value, value) -> value
  def rb_str_replace(str, other)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_str_replace(str, zr_c_result(zr_str_operand(other))))
  end

  # rb_str_substr: `str[beg, len]` by characters, or nil.
  #: (value, word, word) -> value
  def rb_str_substr(str, beg, len)
    Machine.gates_enter
    zr_c_entered()
    # Both Integers come first: a word in `args` roots nothing.
    from = zr_int_from_word(beg)
    count = zr_int_from_word(len)
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(from))
    Machine.store64(args, 8, Machine.word(count))
    zr_c_result(zr_send(str, Machine.id(:[]), 2, args))
  end

  # rb_str_intern: the Symbol of a String.
  #: (value) -> value
  def rb_str_intern(str)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(str, Machine.id(:to_sym), 0, Machine.ptr(0)))
  end

  # rb_sym2str: the frozen name of a Symbol.
  #: (value) -> value
  def rb_sym2str(sym)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(sym, Machine.id(:name), 0, Machine.ptr(0)))
  end

  # rb_str_encode: `str.encode(to, **opts)`. The flags of a C caller
  # that gives no options are the default ones.
  #: (value, value, i32, value) -> value
  def rb_str_encode(str, to, ecflags, ecopts)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(to))
    if ecopts == QNIL
      return zr_c_result(zr_send(str, Machine.id(:encode), 1, args))
    end
    Machine.store64(args, 8, Machine.word(ecopts))
    zr_c_result(zr_capi_send_kw(str, Machine.id(:encode), 2, args))
  end

  # rb_str_concat: `str << obj`, a String or a codepoint.
  #: (value, value) -> value
  def rb_str_concat(str, obj)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(str, Machine.id(:<<), obj)
  end

  # rb_str_split: `str.split(sep)` with a C string separator.
  #: (value, ptr) -> value
  def rb_str_split(str, sep)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(str, Machine.id(:split), zr_str_new(sep, zr_cstr_len(sep)))
  end

  # rb_enc_str_buf_cat: appends `len` bytes at `bytes` in `enc`, as
  # rb_enc_cr_str_buf_cat joins two encodings.
  #: (value, ptr, word, ptr) -> value
  def rb_enc_str_buf_cat(str, bytes, len, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(str, Machine.id(:buf_cat), zr_capi_str(bytes, len, zr_capi_enc_index(enc)))
  end

  # rb_str_conv_enc: `str` from `from` (its own encoding for NULL) to
  # `to`, or `str` itself when it needs no conversion or cannot have one.
  #: (value, ptr, ptr) -> value
  def rb_str_conv_enc(str, from, to)
    Machine.gates_enter
    zr_c_entered()
    if to == 0
      return str
    end
    source = from == 0 ? zr_str_encoding_index(str) : zr_capi_enc_index(from)
    target = zr_capi_enc_index(to)
    if source == target
      return str
    end
    if (zr_enc_ascii_compat_p(target) && zr_enc_ascii_compat_p(source) && zr_str_ascii_bytes_p(str)) || target == ENC_BINARY
      if zr_str_encoding_index(str) == target
        return str
      end
      return zr_str_set_index(zr_str_copy_encoding(zr_str_new(RString[str].ptr, RString[str].len), str), target)
    end
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(zr_capi_encoding_object(target)))
    Machine.store64(args, 8, Machine.word(zr_capi_encoding_object(source)))
    converted = zr_send(str, Machine.id(:encode), 2, args)
    if converted == QUNDEF
      # Some error: the String as it was, as CRuby gives it.
      Task[zr_task()].pending = Machine.value(QNIL)
      return str
    end
    converted
  end

  # rb_external_str_new_with_enc: bytes read from outside, in `enc`, in
  # Encoding.default_internal when there is one and it can take them.
  #: (ptr, word, ptr) -> value
  def rb_external_str_new_with_enc(bytes, len, enc)
    Machine.gates_enter
    zr_c_entered()
    index = zr_capi_enc_index(enc)
    if bytes == 0
      return zr_capi_str(bytes, len, index)
    end
    ascii = zr_bytes_ascii_only_p(bytes, len)
    if index == ENC_BINARY || (index == ENC_USASCII && !ascii)
      return zr_capi_str(bytes, len, ENC_BINARY)
    end
    internal = zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:default_internal), 0, Machine.ptr(0)))
    if internal == QNIL
      return zr_capi_str(bytes, len, index)
    end
    inner = zr_fix2long(zr_c_result(zr_send(internal, Machine.id(:index), 0, Machine.ptr(0))))
    if inner == index
      return zr_capi_str(bytes, len, index)
    end
    if index == ENC_USASCII || (zr_enc_ascii_compat_p(index) && ascii)
      return zr_capi_str(bytes, len, inner)
    end
    s = zr_capi_str(bytes, len, index)
    args = Machine.slot(8)
    Machine.store64(args, 0, Machine.word(internal))
    converted = zr_send(s, Machine.id(:encode), 1, args)
    if converted == QUNDEF
      Task[zr_task()].pending = Machine.value(QNIL)
      return s
    end
    converted
  end

  # rb_str_new_frozen: `str` when it is frozen, else a frozen copy.
  #: (value) -> value
  def rb_str_new_frozen(str)
    Machine.gates_enter
    zr_c_entered()
    zr_frozen_p(str) ? str : zr_str_new_frozen_m(str)
  end

  # rb_str_freeze: freezes `str` and returns it.
  #: (value) -> value
  def rb_str_freeze(str)
    Machine.gates_enter
    zr_c_entered()
    zr_obj_freeze(str, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL))
  end

  # rb_str_append and rb_str_buf_append: `str << other` for a String,
  # with the encodings that `<<` checks.
  #: (value, value) -> value
  def rb_str_append(str, other)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(str, Machine.id(:<<), other)
  end

  #: (value, value) -> value
  def rb_str_buf_append(str, other)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(str, Machine.id(:<<), other)
  end

  # rb_str_plus: `a + b`, a new String.
  #: (value, value) -> value
  def rb_str_plus(a, b)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(a, Machine.id(:+), b)
  end

  # rb_str_dump: `str.dump`.
  #: (value) -> value
  def rb_str_dump(str)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(str, Machine.id(:dump), 0, Machine.ptr(0)))
  end

  # rb_str_times: `str * times`, a new String.
  #: (value, value) -> value
  def rb_str_times(str, times)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(str, Machine.id(:*), times)
  end

  # rb_str_cmp: -1, 0 or 1, as `a <=> b` orders two Strings.
  #: (value, value) -> i32
  def rb_str_cmp(a, b)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_fix2long(zr_capi_call1(a, Machine.id(:<=>), b)))
  end

  # rb_str_export_to_enc: `str` in the encoding `enc`.
  #: (value, ptr) -> value
  def rb_str_export_to_enc(str, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(str, Machine.id(:encode), zr_capi_encoding_object(zr_capi_enc_index(enc)))
  end

  # rb_enc_str_coderange: the coderange of `str` (ENC_CODERANGE_7BIT,
  # _VALID or _BROKEN), which this scans for when it is not known yet.
  #: (value) -> i32
  def rb_enc_str_coderange(str)
    Machine.gates_enter
    zr_c_entered()
    zr_str_ascii_bytes_p(str)
    cr = RBasic[str].flags & FL_CR_MASK
    if cr == 0
      valid = zr_c_result(zr_send(str, Machine.id(:valid_encoding?), 0, Machine.ptr(0)))
      cr = valid == QTRUE ? FL_CR_VALID : FL_CR_BROKEN
      zr_str_set_coderange(str, cr)
    end
    Machine.i32(cr)
  end

  # rb_enc_strlen: the characters of the bytes from `p` to `e` in `enc`;
  # a byte that starts no character counts as one, as String#length
  # counts it.
  #: (ptr, ptr, ptr) -> word
  def rb_enc_strlen(p, e, enc)
    Machine.gates_enter
    zr_c_entered()
    s = zr_str_new_at(p, e - p, zr_capi_enc_index(enc))
    zr_fix2long(zr_c_result(zr_send(s, Machine.id(:length), 0, Machine.ptr(0))))
  end

  # rb_enc_codepoint_len: the codepoint of the character at `p` in `enc`,
  # and its length in bytes into `*len` (when `len` is not NULL). Raises
  # ArgumentError for no bytes or for bytes that are not a character.
  #: (ptr, ptr, ptr, ptr) -> word
  def rb_enc_codepoint_len(p, e, len, enc)
    Machine.gates_enter
    zr_c_entered()
    s = zr_str_new_at(p, e > p ? e - p : 0, zr_capi_enc_index(enc))
    first = zr_capi_call1(s, Machine.id(:[]), zr_fix(0))
    if first == QNIL
      first = s
    end
    code = zr_c_result(zr_send(first, Machine.id(:ord), 0, Machine.ptr(0)))
    if len != 0
      Machine.store32(len, 0, Machine.i32(RString[first].len))
    end
    zr_capi_long(code)
  end

  # rb_fix2str: `fix.to_s(base)`.
  #: (value, i32) -> value
  def rb_fix2str(fix, base)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(fix, Machine.id(:to_s), zr_fix(Machine.sword(base)))
  end

  # rb_cstr2inum: the Integer that the C string `text` writes in `base`,
  # as String#to_i reads it. Base 0 is ruby 4.0's strict base 10: no
  # prefix, and text that is not a number raises, as Integer(text, 10).
  #: (ptr, i32) -> value
  def rb_cstr2inum(text, base)
    Machine.gates_enter
    zr_c_entered()
    str = zr_str_new(text, zr_cstr_len(text))
    if Machine.sword(base) == 0
      args = Machine.slot(16)
      Machine.store64(args, 0, Machine.word(str))
      Machine.store64(args, 8, Machine.word(zr_fix(10)))
      return zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:Integer), 2, args))
    end
    zr_capi_call1(str, Machine.id(:to_i), zr_fix(Machine.sword(base)))
  end

  # rb_sym_to_s: `sym.to_s`, a new String.
  #: (value) -> value
  def rb_sym_to_s(sym)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(sym, Machine.id(:to_s), 0, Machine.ptr(0)))
  end

  # rb_str_subseq: the `len` bytes of `str` from byte `beg`, in its
  # encoding.
  #: (value, word, word) -> value
  def rb_str_subseq(str, beg, len)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(zr_fix(beg)))
    Machine.store64(args, 8, Machine.word(zr_fix(len)))
    zr_c_result(zr_send(str, Machine.id(:byteslice), 2, args))
  end

  # rb_external_str_new: a String of the `len` bytes at `bytes` in the
  # default external encoding.
  #: (ptr, word) -> value
  def rb_external_str_new(bytes, len)
    Machine.gates_enter
    zr_c_entered()
    enc = zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:default_external), 0, Machine.ptr(0)))
    zr_capi_str(bytes, len, zr_fix2long(zr_c_result(zr_send(enc, Machine.id(:index), 0, Machine.ptr(0)))))
  end

  # rb_cstr_to_dbl: the Float that the C string `text` writes; with
  # `badcheck`, text that is not one raises as Float() does, else it reads
  # as String#to_f does.
  #: (ptr, i32) -> f64
  def rb_cstr_to_dbl(text, badcheck)
    Machine.gates_enter
    zr_c_entered()
    str = zr_str_new(text, zr_cstr_len(text))
    f = Machine.value(QNIL)
    if Machine.sword(badcheck) != 0
      f = zr_capi_call1(zr_global(G_KERNEL), Machine.id(:Float), str)
    else
      f = zr_c_result(zr_send(str, Machine.id(:to_f), 0, Machine.ptr(0)))
    end
    zr_float_value(f)
  end

  # ruby_strtod: C's strtod, which sets `*end` past the number it read.
  #: (ptr, ptr) -> f64
  def ruby_strtod(text, stop)
    Machine.gates_enter
    zr_c_entered()
    Libc.strtod(text, stop)
  end

  # rb_cstr_to_inum: rb_cstr2inum with `badcheck` given: with it, text
  # that is not a whole number raises, as Integer(text, base) does.
  #: (ptr, i32, i32) -> value
  def rb_cstr_to_inum(text, base, badcheck)
    Machine.gates_enter
    zr_c_entered()
    str = zr_str_new(text, zr_cstr_len(text))
    b = Machine.sword(base)
    if Machine.sword(badcheck) != 0
      args = Machine.slot(16)
      Machine.store64(args, 0, Machine.word(str))
      Machine.store64(args, 8, Machine.word(zr_fix(b == 0 ? 10 : b)))
      return zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:Integer), 2, args))
    end
    zr_capi_call1(str, Machine.id(:to_i), zr_fix(b == 0 ? 10 : b))
  end

  # rb_str_equal: String#== of `a` and `b`, as Qtrue or Qfalse.
  #: (value, value) -> value
  def rb_str_equal(a, b)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(a, Machine.id(:==), b)
  end

  # rb_str_update: `str[beg, len] = val`.
  #: (value, word, word, value) -> void
  def rb_str_update(str, beg, len, val)
    Machine.gates_enter
    zr_c_entered()
    from = zr_int_from_word(beg)
    count = zr_int_from_word(len)
    args = Machine.slot(24)
    Machine.store64(args, 0, Machine.word(from))
    Machine.store64(args, 8, Machine.word(count))
    Machine.store64(args, 16, Machine.word(val))
    zr_c_result(zr_send(str, Machine.id(:[]=), 3, args))
  end

  # rb_str_strlen and rb_str_length: the characters of `str`, as a long
  # and as an Integer.
  #: (value) -> word
  def rb_str_strlen(str)
    Machine.gates_enter
    zr_c_entered()
    zr_fix2long(zr_c_result(zr_send(str, Machine.id(:length), 0, Machine.ptr(0))))
  end

  #: (value) -> value
  def rb_str_length(str)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(str, Machine.id(:length), 0, Machine.ptr(0)))
  end

  # rb_str_to_str: `obj` as a String, through `to_str`.
  #: (value) -> value
  def rb_str_to_str(obj)
    Machine.gates_enter
    zr_c_entered()
    v = zr_capi_check_convert(obj, T_STRING, Machine.bytes("String"), 6, Machine.id(:to_str))
    if v == QNIL
      return zr_capi_convert(obj, Machine.bytes("String"), 6, Machine.id(:to_str), true)
    end
    v
  end

  # rb_str_capacity: the bytes that `str` holds before it grows.
  #: (value) -> word
  def rb_str_capacity(str)
    Machine.gates_enter
    zr_c_entered()
    RString[str].capa
  end

  # rb_str_modify_expand: makes `str` changeable, with room for `expand`
  # bytes past its length.
  #: (value, word) -> void
  def rb_str_modify_expand(str, expand)
    Machine.gates_enter
    zr_c_entered()
    if expand < 0
      zr_c_raise(zr_global(G_ARGUMENT_ERROR), Machine.bytes("negative expanding string size"), 30)
    end
    zr_capi_str_modify(str)
    zr_str_reserve(str, RString[str].len + expand)
  end

  # rb_str_tmp_new: a binary String of `len` bytes that C fills.
  #: (word) -> value
  def rb_str_tmp_new(len)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(Machine.ptr(0), len, ENC_BINARY)
  end

  # rb_str_to_dbl: the Float that `str` reads as: a strict read
  # (`Float(str)`) when `badcheck` is not 0, else String#to_f.
  #: (value, i32) -> f64
  def rb_str_to_dbl(str, badcheck)
    Machine.gates_enter
    zr_c_entered()
    if Machine.sword(badcheck) != 0
      return zr_float_value(zr_capi_call1(zr_global(G_KERNEL), Machine.id(:Float), str))
    end
    zr_float_value(zr_c_result(zr_send(str, Machine.id(:to_f), 0, Machine.ptr(0))))
  end

  # rb_str2inum: the Integer that `str` starts with, in `base`, as
  # String#to_i reads it.
  #: (value, i32) -> value
  def rb_str2inum(str, base)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.sword(base)
    zr_capi_call1(str, Machine.id(:to_i), zr_fix(b == 0 ? 10 : b))
  end

  # rb_must_asciicompat: Encoding::CompatibilityError for a String whose
  # encoding is not ASCII-compatible.
  #: (value) -> void
  def rb_must_asciicompat(str)
    Machine.gates_enter
    zr_c_entered()
    enc = zr_c_result(zr_send(str, Machine.id(:encoding), 0, Machine.ptr(0)))
    if zr_c_result(zr_send(enc, Machine.id(:ascii_compatible?), 0, Machine.ptr(0))) != QTRUE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("ASCII incompatible encoding: "), 29)
      zr_buf_str(b, zr_c_result(zr_send(enc, Machine.id(:to_s), 0, Machine.ptr(0))))
      zr_c_result(zr_raise_buf(zr_capi_nested(Machine.id(:Encoding), Machine.id(:CompatibilityError)), b))
    end
  end

  # rb_memsearch: where the `m` bytes at `x` first are in the `n` bytes at
  # `y`, or -1.
  #: (ptr, word, ptr, word, ptr) -> word
  def rb_memsearch(x, m, y, n, enc)
    Machine.gates_enter
    zr_c_entered()
    at = 0
    while at + m <= n
      if zr_bytes_eq(y + at, m, x, m)
        return at
      end
      at += 1
    end
    0 - 1
  end

  # rb_str_free: frees nothing; the collector frees a String.
  #: (value) -> void
  def rb_str_free(str)
    Machine.gates_enter
    zr_c_entered()
  end

  # rb_uv_to_utf8: the UTF-8 bytes of the code point `uv` at `buf`, and
  # their count.
  #: (ptr, word) -> i32
  def rb_uv_to_utf8(buf, uv)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_onig_write(RbEncoding[zr_capi_encoding(ENC_UTF8)].onig, uv, buf))
  end

  # rb_str_new_shared: a new String with the bytes of `str` (CRuby shares
  # its buffer; zr copies it).
  #: (value) -> value
  def rb_str_new_shared(str)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(str, Machine.id(:dup), 0, Machine.ptr(0)))
  end

  # rb_str_to_interned_str: the frozen, deduplicated String of `str`
  # (`-str`).
  #: (value) -> value
  def rb_str_to_interned_str(str)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(str, Machine.id(:-@), 0, Machine.ptr(0)))
  end

  # rb_str_buf_cat_ascii: appends the ASCII C string `text`.
  #: (value, ptr) -> value
  def rb_str_buf_cat_ascii(str, text)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(str, Machine.id(:<<), zr_str_new(text, zr_cstr_len(text)))
  end
end
