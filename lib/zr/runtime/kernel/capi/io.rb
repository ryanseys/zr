module Zr::Kern
  # The C API's writes to an IO object, through its Ruby methods, errno,
  # and the SystemCallError of an errno. The IO objects themselves are in
  # io_object.rb.

  # rb_io_write: `io.write(str)`.
  #: (value, value) -> value
  def rb_io_write(io, str)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(io, Machine.id(:write), str)
  end

  # rb_io_addstr: `io.write(str)`, then `io`. An extension may define its
  # own `<<` as this function, so it writes through `write`, as ruby's
  # does, not through `<<`.
  #: (value, value) -> value
  def rb_io_addstr(io, str)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(io, Machine.id(:write), str)
    io
  end

  # rb_io_print: each argument through `out.write`, with `$,` between and
  # `$\` after, as IO#print writes them; `$_` when there is none.
  #: (i32, ptr, value) -> value
  def rb_io_print(argc, argv, out)
    Machine.gates_enter
    zr_c_entered()
    n = Machine.sword(argc)
    if n == 0
      zr_capi_call1(out, Machine.id(:write), zr_gvar_get(Machine.id(:$_)))
    end
    sep = zr_gvar_get(Machine.id(:$,))
    i = 0
    while i < n
      if i > 0 && sep != QNIL
        zr_capi_call1(out, Machine.id(:write), sep)
      end
      zr_capi_call1(out, Machine.id(:write), Machine.value(Machine.load64(argv + (i * 8), 0)))
      i += 1
    end
    tail = zr_gvar_get(Machine.id(:$\))
    if tail != QNIL
      zr_capi_call1(out, Machine.id(:write), tail)
    end
    Machine.value(QNIL)
  end

  # rb_io_printf: `out.write(format(*args))`.
  #: (i32, ptr, value) -> value
  def rb_io_printf(argc, argv, out)
    Machine.gates_enter
    zr_c_entered()
    text = zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:format), Machine.sword(argc), argv))
    zr_capi_call1(out, Machine.id(:write), text)
    Machine.value(QNIL)
  end

  # rb_io_puts: each argument and a newline through `out.write`, as
  # IO#puts writes them (`IO.c_puts`): an Array's elements one a line, an
  # object marked before its #to_ary runs, so one inside itself is
  # `[...]`, and one newline when there is no argument.
  #: (i32, ptr, value) -> value
  def rb_io_puts(argc, argv, out)
    Machine.gates_enter
    zr_c_entered()
    n = Machine.sword(argc)
    objects = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(objects, Machine.value(Machine.load64(argv + (i * 8), 0)))
      i += 1
    end
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(out))
    Machine.store64(args, 8, Machine.word(objects))
    zr_c_result(zr_send(zr_core_class(Machine.id(:IO)), Machine.id(:c_puts), 2, args))
  end

  # rb_eof_error: raises EOFError, `end of file reached`.
  #: () -> void
  def rb_eof_error
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_raise_msg(zr_core_class(Machine.id(:EOFError)), Machine.bytes("end of file reached"), 19))
  end

  # rb_errno_ptr: where this thread's errno is, which C's `errno` reads
  # through.
  #: () -> ptr
  def rb_errno_ptr
    Machine.gates_enter
    zr_c_entered()
    zr_os_errno_ptr()
  end

  # rb_syserr_new_str: `SystemCallError.new(message, errno)`, which is the
  # Errno class of `errno` (Errno::ENOENT for 2). `message` may be nil.
  #: (i32, value) -> value
  def rb_syserr_new_str(errno, message)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_syserr(Machine.sword(errno), message)
  end

  # rb_syserr_fail_str: raises it.
  #: (i32, value) -> void
  def rb_syserr_fail_str(errno, message)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_raise(zr_capi_syserr(Machine.sword(errno), message)))
  end

  # rb_syserr_fail: the same, with a C string or NULL.
  #: (i32, ptr) -> void
  def rb_syserr_fail(errno, message)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_raise(zr_capi_syserr(Machine.sword(errno), zr_capi_cstr_or_nil(message))))
  end

  # rb_sys_fail and rb_sys_fail_str: raise the error of errno as it is now.
  #: (ptr) -> void
  def rb_sys_fail(message)
    Machine.gates_enter
    zr_c_entered()
    errno = zr_os_errno()
    zr_c_result(zr_raise(zr_capi_syserr(errno, zr_capi_cstr_or_nil(message))))
  end

  #: (value) -> void
  def rb_sys_fail_str(message)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_raise(zr_capi_syserr(zr_os_errno(), message)))
  end

  #: (word, value) -> value
  def zr_capi_syserr(errno, message)
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(message))
    Machine.store64(args, 8, Machine.word(zr_fix(errno)))
    zr_c_result(zr_send(zr_core_class(Machine.id(:SystemCallError)), Machine.id(:new), 2, args))
  end

  # A C string as a String, or nil for NULL.
  #: (ptr) -> value
  def zr_capi_cstr_or_nil(text)
    text == 0 ? Machine.value(QNIL) : zr_str_new(text, zr_cstr_len(text))
  end

  # rb_get_path: the path that `obj` names, a String or what its
  # `to_path` gives, as File.path checks it.
  #: (value) -> value
  def rb_get_path(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_core_class(Machine.id(:File)), Machine.id(:path), obj)
  end
end
