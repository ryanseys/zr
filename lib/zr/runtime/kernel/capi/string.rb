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
end
