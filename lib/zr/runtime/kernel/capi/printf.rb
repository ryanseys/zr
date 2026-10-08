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
end
