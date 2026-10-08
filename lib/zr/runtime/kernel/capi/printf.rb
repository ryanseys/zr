module Zr::Kern
  # The C API's printf functions. Each takes a C format and variadic
  # arguments (Machine.stack_args), or a va_list, and gives them to the
  # format of core/c_format.rb. RB_WARN_CATEGORY_* are the categories of
  # rb_category_warn.
  WARN_CATEGORY_DEPRECATED = 1
  WARN_CATEGORY_EXPERIMENTAL = 2
  WARN_CATEGORY_PERFORMANCE = 3
  WARN_CATEGORY_STRICT_UNUSED_BLOCK = 4

  # rb_sprintf: a new String from the format.
  #: (ptr) -> value
  def rb_sprintf(fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    zr_c_result(zr_c_format(fmt, list))
  end

  # rb_vsprintf: the same, with C's va_list.
  #: (ptr, ptr) -> value
  def rb_vsprintf(fmt, ap)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_from_c(list, ap)
    zr_c_result(zr_c_format(fmt, list))
  end

  # rb_raise: raises `klass` with the formatted message.
  #: (value, ptr) -> void
  def rb_raise(klass, fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    message = zr_c_result(zr_c_format(fmt, list))
    zr_c_result(zr_raise(zr_c_result(zr_exc_new_str(klass, message))))
  end

  # rb_bug: ruby's own bug, which ends the process.
  #: (ptr) -> void
  def rb_bug(fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    zr_capi_bug(zr_c_format(fmt, list))
  end

  # rb_warn: a warning, unless $VERBOSE is nil.
  #: (ptr) -> void
  def rb_warn(fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    zr_capi_warn(zr_c_result(zr_c_format(fmt, list)))
  end

  # rb_warning: a warning only under -w ($VERBOSE true).
  #: (ptr) -> void
  def rb_warning(fmt)
    Machine.gates_enter
    zr_c_entered()
    if zr_gvar_get(Machine.id(:$VERBOSE)) != QTRUE
      return
    end
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    zr_capi_warn(zr_c_result(zr_c_format(fmt, list)))
  end

  # rb_category_warn: rb_warn, if the category's warnings are on.
  #: (i32, ptr) -> void
  def rb_category_warn(category, fmt)
    Machine.gates_enter
    zr_c_entered()
    if zr_gvar_get(Machine.id(:$VERBOSE)) == QNIL || !zr_capi_category_on(Machine.sword(category))
      return
    end
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    zr_capi_warn(zr_c_result(zr_c_format(fmt, list)))
  end

  # rb_category_warning: rb_warning, if the category's warnings are on.
  #: (i32, ptr) -> void
  def rb_category_warning(category, fmt)
    Machine.gates_enter
    zr_c_entered()
    if zr_gvar_get(Machine.id(:$VERBOSE)) != QTRUE || !zr_capi_category_on(Machine.sword(category))
      return
    end
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    zr_capi_warn(zr_c_result(zr_c_format(fmt, list)))
  end

  # Writes `message` as rb_warn does: `file:line: warning: message`.
  #: (value) -> void
  def zr_capi_warn(message)
    zr_warn_here(RString[message].ptr, RString[message].len)
  end

  # Whether `Warning[category]` is on for an RB_WARN_CATEGORY_* number.
  #: (word) -> bool
  def zr_capi_category_on(category)
    name = Machine.id(:deprecated)
    if category == WARN_CATEGORY_EXPERIMENTAL
      name = Machine.id(:experimental)
    elsif category == WARN_CATEGORY_PERFORMANCE
      name = Machine.id(:performance)
    elsif category == WARN_CATEGORY_STRICT_UNUSED_BLOCK
      name = Machine.id(:strict_unused_block)
    end
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(zr_sym(name)))
    on = zr_c_result(zr_send(zr_core_class(Machine.id(:Warning)), Machine.id(:[]), 1, arg))
    on != QFALSE && on != QNIL
  end

  # rb_bug's end: `[BUG] message` on stderr, then abort.
  #: (value) -> void
  def zr_capi_bug(message)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("[BUG] "), 6)
    if message != QUNDEF
      zr_buf_str(b, message)
    end
    zr_buf_byte(b, 10)
    zr_bug(Buf[b].ptr, Buf[b].len)
  end

  # ruby_snprintf: writes the format into the `n` bytes at `out`, cut to
  # fit with its NUL, and returns the length of the whole text.
  #: (ptr, word, ptr) -> i32
  def ruby_snprintf(out, n, fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    zr_capi_snprintf(out, n, zr_c_result(zr_c_format(fmt, list)))
  end

  # ruby_vsnprintf: the same, with C's va_list.
  #: (ptr, word, ptr, ptr) -> i32
  def ruby_vsnprintf(out, n, fmt, ap)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_from_c(list, ap)
    zr_capi_snprintf(out, n, zr_c_result(zr_c_format(fmt, list)))
  end

  #: (ptr, word, value) -> i32
  def zr_capi_snprintf(out, n, text)
    len = RString[text].len
    if n > 0
      fits = len < n ? len : n - 1
      zr_memcpy(out, RString[text].ptr, fits)
      Machine.store8(out + fits, 0, Machine.i8(0))
    end
    Machine.i32(len)
  end

  # rb_fatal: ends the program with the formatted message as `fatal`,
  # which no rescue catches: the at_exit handlers run, the message goes to
  # stderr, and the status is 1, as in ruby. (Ruby also runs the ensure
  # clauses on the way out; zr does not.)
  #: (ptr) -> void
  def rb_fatal(fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    message = zr_c_result(zr_c_format(fmt, list))
    exc = zr_c_result(zr_exc_new_str(zr_fatal_class(), message))
    Libc.exit(Machine.i32(zr_program_end(exc)))
  end

  # rb_enc_sprintf: rb_sprintf's String in the encoding `enc`.
  #: (ptr, ptr) -> value
  def rb_enc_sprintf(enc, fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    str = zr_c_result(zr_c_format(fmt, list))
    zr_capi_associate(str, zr_capi_enc_index(enc))
    str
  end

  # rb_str_catf and rb_str_vcatf: append the formatted text to `str`.
  #: (value, ptr) -> value
  def rb_str_catf(str, fmt)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_start(list, Machine.stack_args)
    zr_capi_call1(str, Machine.id(:<<), zr_c_result(zr_c_format(fmt, list)))
  end

  #: (value, ptr, ptr) -> value
  def rb_str_vcatf(str, fmt, ap)
    Machine.gates_enter
    zr_c_entered()
    list = Machine.slot(VA_LIST_BYTES)
    zr_va_from_c(list, ap)
    zr_capi_call1(str, Machine.id(:<<), zr_c_result(zr_c_format(fmt, list)))
  end
end
