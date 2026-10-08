module Zr::Kern
  # The C API of IO objects: their struct rb_io (GetOpenFile), their
  # descriptors and modes, and the IO methods that C calls by function.
  # Each one goes through the IO's Ruby methods, so a subclass's own
  # methods run, as in CRuby's.

  # rb_io_taint_check: the companion through which C reads the struct of
  # the IO `io` (`RFILE(rb_io_taint_check(io))->fptr`), after the check
  # that `io` is not frozen. Another object is its own answer.
  #: (value) -> value
  def rb_io_taint_check(io)
    Machine.gates_enter
    zr_c_entered()
    if zr_frozen_p(io)
      zr_c_result(zr_frozen_error(io))
    end
    if zr_capi_builtin_type(io) != T_FILE
      return io
    end
    key = zr_sym(Machine.id(:__rfile__))
    f = zr_hidden_get(io, key)
    if f == QNIL
      f = zr_rfile_new(io)
      zr_hidden_set(io, key, f)
    end
    f
  end

  # rb_io_check_closed: raises IOError for a closed stream, and fills the
  # struct `fptr` from its IO: its descriptor and its FMODE_* bits.
  #: (ptr) -> void
  def rb_io_check_closed(fptr)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fptr_fill(fptr)
  end

  #: (ptr) -> void
  def zr_capi_fptr_fill(fptr)
    io = zr_capi_fptr_io(fptr)
    fields = zr_c_result(zr_send(io, Machine.id(:struct_fields), 0, Machine.ptr(0)))
    Machine.store32(fptr, RB_IO_FD, Machine.i32(zr_fix2long(zr_ary_at(fields, 0))))
    Machine.store32(fptr, RB_IO_MODE, Machine.i32(zr_fix2long(zr_ary_at(fields, 1))))
  end

  #: (ptr) -> value
  def zr_capi_fptr_io(fptr)
    Machine.value(Machine.load64(fptr, RB_IO_SELF))
  end

  # rb_io_check_readable, rb_io_check_char_readable and
  # rb_io_check_writable: the IOError of a closed stream, or of one not
  # opened for the access.
  #: (ptr) -> void
  def rb_io_check_readable(fptr)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fptr_access(fptr, FMODE_READABLE, Machine.bytes("not opened for reading"), 22)
  end

  #: (ptr) -> void
  def rb_io_check_char_readable(fptr)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fptr_access(fptr, FMODE_READABLE, Machine.bytes("not opened for reading"), 22)
  end

  #: (ptr) -> void
  def rb_io_check_writable(fptr)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fptr_access(fptr, FMODE_WRITABLE, Machine.bytes("not opened for writing"), 22)
  end

  FMODE_READABLE = 1
  FMODE_WRITABLE = 2

  #: (ptr, word, ptr, word) -> void
  def zr_capi_fptr_access(fptr, bit, message, len)
    zr_capi_fptr_fill(fptr)
    if (Machine.u32(Machine.load32(fptr, RB_IO_MODE)) & bit) == 0
      zr_c_raise(zr_core_class(Machine.id(:IOError)), message, len)
    end
  end

  # rb_io_set_nonblock: makes the stream's descriptor return EAGAIN in
  # place of a wait.
  #: (ptr) -> void
  def rb_io_set_nonblock(fptr)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fptr_fill(fptr)
    fd = zr_fix(Machine.sword(Machine.load32(fptr, RB_IO_FD)))
    failed = zr_io_set_nonblock(fd, zr_fix(1))
    if zr_fix2long(failed) < 0
      zr_capi_sys_fail(0 - zr_fix2long(failed))
    end
  end

  # rb_io_synchronized: makes the stream write each write at once.
  #: (ptr) -> void
  def rb_io_synchronized(fptr)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_capi_fptr_io(fptr), Machine.id(:sync=), Machine.value(QTRUE))
  end

  # rb_io_descriptor: the descriptor of `io`, by its `fileno`.
  #: (value) -> i32
  def rb_io_descriptor(io)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(zr_fix2long(zr_c_result(zr_send(io, Machine.id(:fileno), 0, Machine.ptr(0)))))
  end

  # rb_io_mode: the FMODE_* bits of the open stream `io`.
  #: (value) -> i32
  def rb_io_mode(io)
    Machine.gates_enter
    zr_c_entered()
    fields = zr_c_result(zr_send(io, Machine.id(:struct_fields), 0, Machine.ptr(0)))
    Machine.i32(zr_fix2long(zr_ary_at(fields, 1)))
  end

  # rb_io_check_io: `io` as an IO through `to_io`, or nil.
  #: (value) -> value
  def rb_io_check_io(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_convert(io, T_FILE, Machine.bytes("IO"), 2, Machine.id(:to_io))
  end

  # rb_io_get_io: `io` as an IO through `to_io`, else a TypeError.
  #: (value) -> value
  def rb_io_get_io(io)
    Machine.gates_enter
    zr_c_entered()
    v = zr_capi_check_convert(io, T_FILE, Machine.bytes("IO"), 2, Machine.id(:to_io))
    if v == QNIL
      return zr_capi_convert(io, Machine.bytes("IO"), 2, Machine.id(:to_io), true)
    end
    v
  end

  # The IO methods that C calls by function, each one a send:
  # rb_io_flush, rb_io_close, rb_io_gets, rb_io_getbyte, rb_io_eof,
  # rb_io_binmode, rb_io_ascii8bit_binmode, rb_io_path and rb_io_timeout.
  #: (value) -> value
  def rb_io_flush(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:flush))
  end

  #: (value) -> value
  def rb_io_close(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:close))
  end

  #: (value) -> value
  def rb_io_gets(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:gets))
  end

  #: (value) -> value
  def rb_io_getbyte(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:getbyte))
  end

  #: (value) -> value
  def rb_io_eof(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:eof?))
  end

  #: (value) -> value
  def rb_io_binmode(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:binmode))
  end

  #: (value) -> value
  def rb_io_ascii8bit_binmode(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:binmode))
  end

  #: (value) -> value
  def rb_io_path(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:path))
  end

  #: (value) -> value
  def rb_io_timeout(io)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_io_send(io, Machine.id(:timeout))
  end

  #: (value, word) -> value
  def zr_capi_io_send(io, mid)
    zr_c_result(zr_send(io, mid, 0, Machine.ptr(0)))
  end

  # rb_io_wait: waits up to `timeout` (nil: on) for the RUBY_IO_* events
  # of `io`, and gives those that came ready, or false when the time ran
  # out.
  #: (value, value, value) -> value
  def rb_io_wait(io, events, timeout)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(events))
    Machine.store64(args, 8, Machine.word(timeout))
    ready = zr_c_result(zr_send(io, Machine.id(:wait), 2, args))
    ready == QNIL ? Machine.value(QFALSE) : ready
  end

  # rb_cloexec_open: open(2) of the C string `path`, closed across an
  # exec, as each descriptor that ruby opens is. The descriptor, or -1
  # with errno set.
  #: (ptr, i32, i32) -> i32
  def rb_cloexec_open(path, flags, mode)
    Machine.gates_enter
    zr_c_entered()
    zr_os_open(path, Machine.i32(Machine.sword(flags) | O_CLOEXEC), mode)
  end

  # rb_fd_fix_cloexec: makes `fd` close across an exec, except a
  # standard stream.
  #: (i32) -> void
  def rb_fd_fix_cloexec(fd)
    Machine.gates_enter
    zr_c_entered()
    if Machine.sword(fd) > 2
      zr_io_cloexec(zr_fix(Machine.sword(fd)))
    end
  end

  # rb_update_max_fd: ruby's count of descriptors for its fork; zr has
  # none to keep.
  #: (i32) -> void
  def rb_update_max_fd(fd)
    Machine.gates_enter
    zr_c_entered()
  end

  # rb_sys_fail of an errno with no message.
  #: (word) -> void
  def zr_capi_sys_fail(errno)
    zr_c_result(zr_raise(zr_capi_syserr(errno, Machine.value(QNIL))))
  end
end
