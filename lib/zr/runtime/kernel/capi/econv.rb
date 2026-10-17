module Zr::Kern
  # ruby/encoding.h's transcoder (rb_econv_*): an rb_econv_t is a word of
  # C memory that holds an Encoding::Converter, kept alive as a C root
  # while it is open. Each call goes to the converter's C helpers in the
  # core (`Encoding::Converter.c_open` and the rest).

  # The Encoding::Converter class.
  #: () -> value
  def zr_capi_converter_class
    e = zr_const_row_in(zr_core_class(Machine.id(:Encoding)), Machine.id(:Converter), false)
    CEntry[e].value
  end

  # `Encoding::Converter.name(*args)` of the `argc` values at `args`.
  #: (word, word, ptr) -> value
  def zr_capi_converter_call(name, argc, args)
    zr_c_result(zr_send(zr_capi_converter_class(), name, argc, args))
  end

  # rb_econv_prepare_opts: the flag word that `opthash` gives, and into
  # `*ecopts` the options that a converter keeps (nil for none).
  #: (value, ptr) -> i32
  def rb_econv_prepare_opts(opthash, ecopts)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(8)
    Machine.store64(args, 0, Machine.word(opthash))
    pair = zr_capi_converter_call(Machine.id(:c_prepare), 1, args)
    Machine.store64(ecopts, 0, Machine.word(zr_ary_at(pair, 1)))
    Machine.i32(zr_fix2long(zr_ary_at(pair, 0)))
  end

  # rb_econv_prepare_options: the same, with the flags that the caller
  # gives besides.
  #: (value, ptr, i32) -> i32
  def rb_econv_prepare_options(opthash, ecopts, ecflags)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(8)
    Machine.store64(args, 0, Machine.word(opthash))
    pair = zr_capi_converter_call(Machine.id(:c_prepare), 1, args)
    Machine.store64(ecopts, 0, Machine.word(zr_ary_at(pair, 1)))
    Machine.i32(zr_fix2long(zr_ary_at(pair, 0)) | Machine.sword(ecflags))
  end

  # rb_econv_open_opts: a converter from the encoding named `source` to
  # the one named `target`, or NULL where none converts.
  #: (ptr, ptr, i32, value) -> ptr
  def rb_econv_open_opts(source, target, ecflags, ecopts)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_econv_open(source, target, Machine.sword(ecflags), ecopts)
  end

  # rb_econv_open: the same with no options.
  #: (ptr, ptr, i32) -> ptr
  def rb_econv_open(source, target, ecflags)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_econv_open(source, target, Machine.sword(ecflags), Machine.value(QNIL))
  end

  #: (ptr, ptr, word, value) -> ptr
  def zr_capi_econv_open(source, target, ecflags, ecopts)
    args = Machine.slot(32)
    Machine.store64(args, 0, Machine.word(zr_str_new(source, zr_cstr_len(source))))
    Machine.store64(args, 8, Machine.word(zr_str_new(target, zr_cstr_len(target))))
    Machine.store64(args, 16, Machine.word(zr_fix(ecflags)))
    Machine.store64(args, 24, Machine.word(ecopts))
    converter = zr_capi_converter_call(Machine.id(:c_open), 4, args)
    if converter == QNIL
      return Machine.ptr(0)
    end
    ec = zr_xmalloc(8)
    Machine.store64(ec, 0, Machine.word(converter))
    zr_weak_list_push(zr_c_root_addresses(), Machine.value(Machine.word(ec)))
    ec
  end

  # rb_econv_close: drops the converter and frees its word.
  #: (ptr) -> void
  def rb_econv_close(ec)
    Machine.gates_enter
    zr_c_entered()
    zr_c_root_address_drop(ec)
    zr_xfree(ec)
  end

  # rb_econv_convert: converts the bytes from `*sp` to `se` into the room
  # from `*dp` to `de`, and moves both pointers past what it took and
  # wrote. A NULL `sp` gives no more input.
  #: (ptr, ptr, ptr, ptr, ptr, i32) -> i32
  def rb_econv_convert(ec, sp, se, dp, de, flags)
    Machine.gates_enter
    zr_c_entered()
    input = Machine.value(QNIL)
    if Machine.word(sp) != 0 && Machine.load64(sp, 0) != 0
      input = zr_str_new(Machine.ptr(Machine.load64(sp, 0)), Machine.word(se) - Machine.load64(sp, 0))
    end
    args = Machine.slot(32)
    Machine.store64(args, 0, Machine.load64(ec, 0))
    Machine.store64(args, 8, Machine.word(input))
    Machine.store64(args, 16, Machine.word(zr_fix(Machine.word(de) - Machine.load64(dp, 0))))
    Machine.store64(args, 24, Machine.word(zr_fix(Machine.sword(flags))))
    r = zr_capi_converter_call(Machine.id(:c_convert), 4, args)
    if input != QNIL
      Machine.store64(sp, 0, Machine.load64(sp, 0) + zr_fix2long(zr_ary_at(r, 1)))
    end
    out = zr_ary_at(r, 2)
    zr_memcpy(Machine.ptr(Machine.load64(dp, 0)), RString[out].ptr, RString[out].len)
    Machine.store64(dp, 0, Machine.load64(dp, 0) + RString[out].len)
    Machine.i32(zr_fix2long(zr_ary_at(r, 0)))
  end

  # rb_econv_check_error: raises the error of the last conversion, if it
  # had one.
  #: (ptr) -> void
  def rb_econv_check_error(ec)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(8)
    Machine.store64(args, 0, Machine.load64(ec, 0))
    zr_capi_converter_call(Machine.id(:c_check_error), 1, args)
  end

  # rb_econv_str_convert: the whole of `src`, converted.
  #: (ptr, value, i32) -> value
  def rb_econv_str_convert(ec, src, flags)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(24)
    Machine.store64(args, 0, Machine.load64(ec, 0))
    Machine.store64(args, 8, Machine.word(src))
    Machine.store64(args, 16, Machine.word(zr_fix(Machine.sword(flags))))
    zr_capi_converter_call(Machine.id(:c_str_convert), 3, args)
  end

  # rb_str_conv_enc_opts: `str` from `from` to `to`, or `str` itself
  # where that does not convert.
  #: (value, ptr, ptr, i32, value) -> value
  def rb_str_conv_enc_opts(str, from, to, ecflags, ecopts)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_str_conv_opts(str, from, to, Machine.sword(ecflags), ecopts)
  end

  #: (value, ptr, ptr, word, value) -> value
  def zr_capi_str_conv_opts(str, from, to, ecflags, ecopts)
    args = Machine.slot(40)
    Machine.store64(args, 0, Machine.word(str))
    Machine.store64(args, 8, Machine.word(from == 0 ? Machine.value(QNIL) : zr_capi_encoding_object(zr_capi_enc_index(from))))
    Machine.store64(args, 16, Machine.word(to == 0 ? Machine.value(QNIL) : zr_capi_encoding_object(zr_capi_enc_index(to))))
    Machine.store64(args, 24, Machine.word(zr_fix(ecflags)))
    Machine.store64(args, 32, Machine.word(ecopts))
    zr_capi_converter_call(Machine.id(:c_str_conv), 5, args)
  end
end
