module Zr::Kern
  # The C API's encodings. C holds an encoding as CRuby's rb_encoding, an
  # OnigEncodingType, and reads its name, its character lengths and its
  # index inline (rb_enc_name, rb_enc_mbminlen, rb_enc_mbmaxlen). Its
  # inline functions call the struct's function pointers (rb_enc_mbcput,
  # rb_enc_isspace...), which are the defs of onig.rb. Each encoding gets
  # one such struct, made the first time C asks for it and kept for the
  # program (zr_capi_encoding). After CRuby's fields, zr's own: the
  # descriptor through which onig_enc.rb reads the encoding.
  class RbEncoding < Layout
    attr_accessor :precise_mbc_enc_len #: ptr
    attr_accessor :name #: ptr
    attr_accessor :max_enc_len #: i32
    attr_accessor :min_enc_len #: i32
    attr_accessor :is_mbc_newline #: ptr
    attr_accessor :mbc_to_code #: ptr
    attr_accessor :code_to_mbclen #: ptr
    attr_accessor :code_to_mbc #: ptr
    attr_accessor :mbc_case_fold #: ptr
    attr_accessor :apply_all_case_fold #: ptr
    attr_accessor :get_case_fold_codes_by_str #: ptr
    attr_accessor :property_name_to_ctype #: ptr
    attr_accessor :is_code_ctype #: ptr
    attr_accessor :get_ctype_code_range #: ptr
    attr_accessor :left_adjust_char_head #: ptr
    attr_accessor :is_allowed_reverse_match #: ptr
    attr_accessor :case_map #: ptr
    attr_accessor :ruby_encoding_index #: i32
    attr_accessor :flags #: i32
    attr_accessor :onig #: word
  end

  # OnigEncodingType#flags: ONIGENC_FLAG_UNICODE.
  ONIGENC_FLAG_UNICODE = 1

  # The encodings that the table holds: ruby's 103, with room.
  CAPI_ENCODINGS = 128

  # The rb_encoding of the encoding `index`.
  #: (word) -> ptr
  def zr_capi_encoding(index)
    at = Machine.static(:capi_encodings, CAPI_ENCODINGS * 8) + (index * 8)
    enc = Machine.ptr(Machine.load64(at, 0))
    if enc != 0
      return enc
    end
    enc = zr_capi_encoding_struct(index)
    Libc.memset(enc, Machine.i32(0), RbEncoding.size)
    name = zr_c_result(zr_send(zr_capi_encoding_object(index), Machine.id(:name), 0, Machine.ptr(0)))
    copy = zr_xmalloc(RString[name].len + 1)
    zr_memcpy(copy, RString[name].ptr, RString[name].len + 1)
    RbEncoding[enc].name = copy
    RbEncoding[enc].min_enc_len = Machine.i32(zr_capi_enc_min_len(index))
    RbEncoding[enc].max_enc_len = Machine.i32(zr_capi_enc_max_len(index))
    RbEncoding[enc].ruby_encoding_index = Machine.i32(index)
    zr_capi_onig_attach(enc, zr_capi_encoding_object(index))
    Machine.store64(at, 0, Machine.word(enc))
    enc
  end

  # The memory of the struct of the encoding `index`. Ruby exports the
  # structs of ASCII-8BIT, UTF-8 and US-ASCII as data, which
  # ONIG_ENCODING_ASCII and its kin name (`&OnigEncodingASCII`), so
  # theirs are those globals; zr_capi_init fills them before C runs.
  #: (word) -> ptr
  def zr_capi_encoding_struct(index)
    if index == ENC_BINARY
      return Machine.global(:OnigEncodingASCII, RbEncoding.size)
    end
    if index == ENC_UTF8
      return Machine.global(:OnigEncodingUTF_8, RbEncoding.size)
    end
    if index == ENC_USASCII
      return Machine.global(:OnigEncodingUS_ASCII, RbEncoding.size)
    end
    zr_xmalloc(RbEncoding.size)
  end

  # The index of the rb_encoding `enc`; 0 (ASCII-8BIT) for NULL, as
  # rb_enc_to_index gives it.
  #: (ptr) -> word
  def zr_capi_enc_index(enc)
    enc == 0 ? ENC_BINARY : Machine.sword(RbEncoding[enc].ruby_encoding_index)
  end

  # The Encoding object of the encoding `index`.
  #: (word) -> value
  def zr_capi_encoding_object(index)
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(zr_fix(index)))
    zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:at), 1, arg))
  end

  # The fewest bytes of a character in the encoding `index`.
  #: (word) -> word
  def zr_capi_enc_min_len(index)
    if index == ENC_UTF32BE || index == ENC_UTF32LE || index == ENC_UTF32
      return 4
    end
    if index == ENC_UTF16BE || index == ENC_UTF16LE || index == ENC_UTF16
      return 2
    end
    if zr_enc_mb_p(index)
      return OnigEnc[Machine.ptr(zr_enc_mb_descriptor(index))].min_len
    end
    1
  end

  # The most bytes of a character in the encoding `index`.
  #: (word) -> word
  def zr_capi_enc_max_len(index)
    if index == ENC_UTF8 || index == ENC_UTF32BE || index == ENC_UTF32LE || index == ENC_UTF32 || zr_capi_enc_min_len(index) == 2
      return 4
    end
    if zr_enc_mb_p(index)
      return OnigEnc[Machine.ptr(zr_enc_mb_descriptor(index))].max_len
    end
    zr_enc_utf8_like_p(index) ? 4 : 1
  end

  # The encoding index of `obj`: a String's or a Symbol's own, else what
  # its `encoding` gives, else -1 for an object with none.
  #: (value) -> word
  def zr_capi_obj_enc_index(obj)
    if zr_special_p(obj) && !zr_symbol_p(obj)
      return 0 - 1
    end
    if !zr_special_p(obj) && zr_type(obj) == T_STRING
      return zr_str_encoding_index(obj)
    end
    # An Encoding is its own encoding, as rb_enc_get_index reads one.
    if !zr_special_p(obj) && zr_is_a(obj, zr_core_class(Machine.id(:Encoding)))
      return zr_fix2long(zr_c_result(zr_send(obj, Machine.id(:index), 0, Machine.ptr(0))))
    end
    if zr_c_result(zr_check_funcall(obj, Machine.id(:encoding))) == QTRUE
      enc = zr_c_result(zr_send(obj, Machine.id(:encoding), 0, Machine.ptr(0)))
      return zr_fix2long(zr_c_result(zr_send(enc, Machine.id(:index), 0, Machine.ptr(0))))
    end
    0 - 1
  end

  #: () -> ptr
  def rb_utf8_encoding
    Machine.gates_enter
    zr_c_entered()
    zr_capi_encoding(ENC_UTF8)
  end

  #: () -> ptr
  def rb_ascii8bit_encoding
    Machine.gates_enter
    zr_c_entered()
    zr_capi_encoding(ENC_BINARY)
  end

  #: () -> ptr
  def rb_usascii_encoding
    Machine.gates_enter
    zr_c_entered()
    zr_capi_encoding(ENC_USASCII)
  end

  #: () -> i32
  def rb_utf8_encindex
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(ENC_UTF8)
  end

  #: () -> i32
  def rb_ascii8bit_encindex
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(ENC_BINARY)
  end

  #: () -> i32
  def rb_usascii_encindex
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(ENC_USASCII)
  end

  # rb_enc_from_index: the rb_encoding of an index, or NULL for none.
  #: (i32) -> ptr
  def rb_enc_from_index(index)
    Machine.gates_enter
    zr_c_entered()
    i = Machine.sword(index)
    if i < 0 || i >= CAPI_ENCODINGS || zr_c_result(zr_capi_encoding_object(i)) == QNIL
      return Machine.ptr(0)
    end
    zr_capi_encoding(i)
  end

  #: (ptr) -> i32
  def rb_enc_to_index(enc)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_enc_index(enc))
  end

  # rb_enc_from_encoding: the Encoding object of an rb_encoding, or nil.
  #: (ptr) -> value
  def rb_enc_from_encoding(enc)
    Machine.gates_enter
    zr_c_entered()
    enc == 0 ? Machine.value(QNIL) : zr_capi_encoding_object(zr_capi_enc_index(enc))
  end

  # rb_to_encoding: the rb_encoding of an Encoding, or of a name.
  #: (value) -> ptr
  def rb_to_encoding(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_encoding(zr_capi_to_enc_index(obj))
  end

  #: (value) -> i32
  def rb_to_encoding_index(obj)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_to_enc_index(obj))
  end

  # The index of an Encoding, or of the encoding that a name finds
  # (Encoding.find, which raises for an unknown name).
  #: (value) -> word
  def zr_capi_to_enc_index(obj)
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(obj))
    enc = zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:find), 1, arg))
    zr_fix2long(zr_c_result(zr_send(enc, Machine.id(:index), 0, Machine.ptr(0))))
  end

  # rb_define_dummy_encoding: a new dummy encoding named `name`, and its
  # index (`Encoding.c_define_dummy`).
  #: (ptr) -> i32
  def rb_define_dummy_encoding(name)
    Machine.gates_enter
    zr_c_entered()
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(zr_str_new(name, zr_cstr_len(name))))
    Machine.i32(zr_fix2long(zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:c_define_dummy), 1, arg))))
  end

  # rb_enc_find_index: the index of the encoding named `name`, or -1.
  #: (ptr) -> i32
  def rb_enc_find_index(name)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_find_index(name))
  end

  #: (ptr) -> word
  def zr_capi_find_index(name)
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(zr_str_new(name, zr_cstr_len(name))))
    enc = zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:find), 1, arg)
    if enc == QUNDEF
      Task[zr_task()].pending = Machine.value(QNIL)
      return 0 - 1
    end
    zr_fix2long(zr_c_result(zr_send(enc, Machine.id(:index), 0, Machine.ptr(0))))
  end

  # rb_enc_get_index: the encoding index of a String, a Symbol, or an
  # object with an `encoding`; -1 for one with none.
  #: (value) -> i32
  def rb_enc_get_index(obj)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_obj_enc_index(obj))
  end

  # rb_enc_get: the same, as an rb_encoding, or NULL.
  #: (value) -> ptr
  def rb_enc_get(obj)
    Machine.gates_enter
    zr_c_entered()
    index = zr_capi_obj_enc_index(obj)
    index < 0 ? Machine.ptr(0) : zr_capi_encoding(index)
  end

  # rb_enc_set_index and rb_enc_associate_index: a String's encoding,
  # with its bytes as they are.
  #: (value, i32) -> void
  def rb_enc_set_index(obj, index)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_associate(obj, Machine.sword(index))
  end

  #: (value, i32) -> value
  def rb_enc_associate_index(obj, index)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_associate(obj, Machine.sword(index))
    obj
  end

  #: (value, ptr) -> value
  def rb_enc_associate(obj, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_associate(obj, zr_capi_enc_index(enc))
    obj
  end

  #: (value, word) -> void
  def zr_capi_associate(obj, index)
    if zr_special_p(obj) || zr_type(obj) != T_STRING
      return
    end
    if zr_frozen_p(obj)
      zr_c_result(zr_frozen_error(obj))
    end
    zr_str_set_index(obj, index)
  end

  # rb_default_external_encoding and rb_default_internal_encoding (NULL
  # when there is none).
  #: () -> ptr
  def rb_default_external_encoding
    Machine.gates_enter
    zr_c_entered()
    zr_capi_default_encoding(Machine.id(:default_external))
  end

  #: () -> ptr
  def rb_default_internal_encoding
    Machine.gates_enter
    zr_c_entered()
    zr_capi_default_encoding(Machine.id(:default_internal))
  end

  #: (word) -> ptr
  def zr_capi_default_encoding(which)
    enc = zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), which, 0, Machine.ptr(0)))
    if enc == QNIL
      return Machine.ptr(0)
    end
    zr_capi_encoding(zr_fix2long(zr_c_result(zr_send(enc, Machine.id(:index), 0, Machine.ptr(0)))))
  end

  # rb_enc_default_external and rb_enc_default_internal: the Encodings.
  #: () -> value
  def rb_enc_default_external
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:default_external), 0, Machine.ptr(0)))
  end

  #: () -> value
  def rb_enc_default_internal
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:default_internal), 0, Machine.ptr(0)))
  end

  # rb_enc_str_new: a String of `len` bytes at `bytes` in `enc`.
  #: (ptr, word, ptr) -> value
  def rb_enc_str_new(bytes, len, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(bytes, len, zr_capi_enc_index(enc))
  end

  #: (ptr, ptr) -> value
  def rb_enc_str_new_cstr(text, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(text, zr_cstr_len(text), zr_capi_enc_index(enc))
  end

  #: (ptr, word, ptr) -> value
  def rb_enc_str_new_static(bytes, len, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str(bytes, len, zr_capi_enc_index(enc))
  end

  # rb_enc_interned_str: the frozen, shared String of the bytes in
  # `enc` (ASCII-8BIT for NULL), as `-"..."` gives it.
  #: (ptr, word, ptr) -> value
  def rb_enc_interned_str(bytes, len, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_str_intern(zr_capi_str(bytes, len, zr_capi_enc_index(enc)))
  end

  #: (ptr, ptr) -> value
  def rb_enc_interned_str_cstr(text, enc)
    Machine.gates_enter
    zr_c_entered()
    zr_str_intern(zr_capi_str(text, zr_cstr_len(text), zr_capi_enc_index(enc)))
  end

  # rb_enc_find: the rb_encoding named `name`; ASCII-8BIT for a name
  # that no encoding has, as ruby gives it.
  #: (ptr) -> ptr
  def rb_enc_find(name)
    Machine.gates_enter
    zr_c_entered()
    index = zr_capi_find_index(name)
    zr_capi_encoding(index < 0 ? ENC_BINARY : index)
  end

  # rb_enc_dummy_p: 1 for a dummy encoding (UTF-7, ISO-2022-JP), which
  # has no characters of its own, else 0.
  #: (ptr) -> i32
  def rb_enc_dummy_p(enc)
    Machine.gates_enter
    zr_c_entered()
    dummy = zr_c_result(zr_send(zr_capi_encoding_object(zr_capi_enc_index(enc)), Machine.id(:dummy?), 0, Machine.ptr(0)))
    Machine.i32(dummy == QTRUE ? 1 : 0)
  end

  # rb_filesystem_encoding: the encoding of file names.
  #: () -> ptr
  def rb_filesystem_encoding
    Machine.gates_enter
    zr_c_entered()
    zr_capi_encoding(zr_capi_to_enc_index(zr_str_new(Machine.bytes("filesystem"), 10)))
  end

  # rb_enc_check: the encoding that `a` and `b` have together
  # (Encoding.compatible?), else CRuby's Encoding::CompatibilityError.
  #: (value, value) -> ptr
  def rb_enc_check(a, b)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(a))
    Machine.store64(args, 8, Machine.word(b))
    enc = zr_c_result(zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:compatible?), 2, args))
    if enc == QNIL
      Machine.store64(args, 0, Machine.word(zr_capi_encoding_object(zr_capi_obj_enc_index(a))))
      Machine.store64(args, 8, Machine.word(zr_capi_encoding_object(zr_capi_obj_enc_index(b))))
      zr_c_result(zr_send(zr_str_new(Machine.bytes(""), 0), Machine.id(:buf_incompatible), 2, args))
    end
    zr_capi_encoding(zr_capi_to_enc_index(enc))
  end

  # rb_locale_encoding: the encoding of the locale (`Encoding.find("locale")`).
  #: () -> ptr
  def rb_locale_encoding
    Machine.gates_enter
    zr_c_entered()
    zr_capi_encoding(zr_capi_to_enc_index(zr_str_new(Machine.bytes("locale"), 6)))
  end

  # rb_locale_encindex: the index of the locale's encoding.
  #: () -> i32
  def rb_locale_encindex
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_capi_to_enc_index(zr_str_new(Machine.bytes("locale"), 6)))
  end

  # rb_enc_copy: `dst` takes the encoding of `src`.
  #: (value, value) -> void
  def rb_enc_copy(dst, src)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_associate(dst, zr_capi_obj_enc_index(src))
  end

  # rb_find_encoding: the rb_encoding of an Encoding, or of the encoding
  # that a name names; NULL for a name of none.
  #: (value) -> ptr
  def rb_find_encoding(enc)
    Machine.gates_enter
    zr_c_entered()
    found = zr_send(zr_core_class(Machine.id(:Encoding)), Machine.id(:find), 1, zr_capi_one(enc))
    if found == QUNDEF
      Task[zr_task()].pending = Machine.value(QNIL)
      return Machine.ptr(0)
    end
    zr_capi_encoding(zr_fix2long(zr_c_result(zr_send(found, Machine.id(:index), 0, Machine.ptr(0)))))
  end
end
