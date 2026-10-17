module Zr::Kern
  # The format of the C API's printf functions is core Ruby
  # (Kernel::CFormatter, core/c_format.rb). It reads the C call's variadic
  # arguments through these, which take the address of the call's VaList
  # (os/*/va_list.rb) as an Integer.

  # The next argument's 64 bits, as a signed Integer.
  #: (value) -> value
  def zr_va_word(list)
    zr_int_from_word(zr_va_next_word(Machine.ptr(zr_fix2long(list))))
  end

  # The next argument as a C int: its low 32 bits, signed.
  #: (value) -> value
  def zr_va_int(list)
    zr_fix(Machine.sword(Machine.i32(zr_va_next_word(Machine.ptr(zr_fix2long(list))))))
  end

  #: (value) -> value
  def zr_va_double(list)
    zr_float_new(zr_va_next_double(Machine.ptr(zr_fix2long(list))))
  end

  # The next argument, a Value.
  #: (value) -> value
  def zr_va_value(list)
    Machine.value(zr_va_next_word(Machine.ptr(zr_fix2long(list))))
  end

  # The next argument, a C string, as a binary String; nil for NULL.
  #: (value) -> value
  def zr_va_cstr(list)
    p = Machine.ptr(zr_va_next_word(Machine.ptr(zr_fix2long(list))))
    if p == 0
      return Machine.value(QNIL)
    end
    s = zr_str_new(p, zr_cstr_len(p))
    zr_str_set_binary(s)
    s
  end

  # The String that the C format `fmt` gives with the arguments in the
  # VaList at `list`, or undef when a Value's to_s or inspect raised.
  #: (ptr, ptr) -> value
  def zr_c_format(fmt, list)
    args = Machine.slot(16)
    text = zr_str_new(fmt, zr_cstr_len(fmt))
    zr_str_set_binary(text)
    Machine.store64(args, 0, Machine.word(text))
    Machine.store64(args, 8, Machine.word(zr_fix(Machine.word(list))))
    # The runtime's own constant, read as the runtime reads it: C that an
    # allocator runs (`Class#new`, which has no frame of its own) has the
    # program's frame on top, which does not see concealed constants.
    formatter = CEntry[zr_const_row_kept(zr_const_holder(zr_global(G_KERNEL), true), Machine.id(:CFormatter))].value
    zr_send(formatter, Machine.id(:render), 2, args)
  end
end
