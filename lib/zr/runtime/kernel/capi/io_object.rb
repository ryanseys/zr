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
  FMODE_APPEND = 0x40

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

  # rb_file_open and rb_file_open_str: `File.open(path, mode)`, the mode
  # a C string.
  #: (ptr, ptr) -> value
  def rb_file_open(path, mode)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_file_open(zr_str_new(path, zr_cstr_len(path)), mode)
  end

  #: (value, ptr) -> value
  def rb_file_open_str(path, mode)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_file_open(path, mode)
  end

  #: (value, ptr) -> value
  def zr_capi_file_open(path, mode)
    # The mode String comes first: a word in `args` roots nothing.
    flags = zr_str_new(mode, zr_cstr_len(mode))
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(path))
    Machine.store64(args, 8, Machine.word(flags))
    zr_c_result(zr_send(zr_core_class(Machine.id(:File)), Machine.id(:open), 2, args))
  end

  # rb_io_bufwrite: `io.write` of the `size` bytes at `buf`; the bytes it
  # wrote.
  #: (value, ptr, word) -> word
  def rb_io_bufwrite(io, buf, size)
    Machine.gates_enter
    zr_c_entered()
    bytes = zr_capi_str(buf, size, ENC_BINARY)
    zr_fix2long(zr_capi_call1(io, Machine.id(:write), bytes))
  end

  # rb_io_enc_t: the internal and the external encoding, the conversion's
  # flags (an int) and its options.
  class RbIoEnc < Layout
    attr_accessor :enc #: ptr
    attr_accessor :enc2 #: ptr
    attr_accessor :ecflags #: word
    attr_accessor :ecopts #: value
  end

  # rb_io_extract_modeenc: the mode at `*vmode_p` and the options of an
  # open, read as IO.open reads them: `*vmode_p` gets the mode (from the
  # options, if they give it), `*oflags_p` open(2)'s flags, `*fmode_p` the
  # FMODE_* bits, and `*convconfig` the encodings. zr converts with no
  # flags of C's.
  #: (ptr, ptr, value, ptr, ptr, ptr) -> void
  def rb_io_extract_modeenc(vmode_p, vperm_p, opthash, oflags_p, fmode_p, convconfig)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.load64(vmode_p, 0))
    Machine.store64(args, 8, Machine.word(opthash))
    r = zr_c_result(zr_send(zr_core_class(Machine.id(:IO)), Machine.id(:c_modeenc), 2, args))
    Machine.store64(vmode_p, 0, Machine.word(zr_ary_at(r, 0)))
    Machine.store32(oflags_p, 0, Machine.i32(zr_fix2long(zr_ary_at(r, 1))))
    Machine.store32(fmode_p, 0, Machine.i32(zr_fix2long(zr_ary_at(r, 2))))
    RbIoEnc[convconfig].enc = zr_capi_enc_of(zr_ary_at(r, 3))
    RbIoEnc[convconfig].enc2 = zr_capi_enc_of(zr_ary_at(r, 4))
    Machine.store32(convconfig + 16, 0, Machine.i32(0))
    RbIoEnc[convconfig].ecopts = Machine.value(QNIL)
  end

  # rb_io_stdio_file: a stdio FILE on the stream's descriptor, made once
  # with the mode of the stream's access, as curses and curb want it. The
  # FILE stays open: closing it would close the descriptor, which the IO
  # owns.
  #: (ptr) -> ptr
  def rb_io_stdio_file(fptr)
    Machine.gates_enter
    zr_c_entered()
    file = Machine.ptr(Machine.load64(fptr, RB_IO_STDIO))
    if file == 0
      zr_capi_fptr_fill(fptr)
      fmode = Machine.sword(Machine.load32(fptr, RB_IO_MODE))
      fd = Machine.load32(fptr, RB_IO_FD)
      file = zr_os_fdopen(fd, zr_capi_stdio_mode(fmode))
      if file == 0
        errno = zr_os_errno()
        zr_c_result(zr_raise(zr_capi_syserr(errno, zr_capi_cstr_or_nil(Machine.bytes("fdopen")))))
      end
      Machine.store64(fptr, RB_IO_STDIO, Machine.word(file))
    end
    file
  end

  # The fopen mode of a stream's FMODE_* bits, as rb_io_oflags_modestr
  # gives it.
  #: (word) -> ptr
  def zr_capi_stdio_mode(fmode)
    readable = (fmode & FMODE_READABLE) != 0
    if (fmode & FMODE_APPEND) != 0
      return readable ? Machine.bytes("a+") : Machine.bytes("a")
    end
    if (fmode & FMODE_WRITABLE) == 0
      return Machine.bytes("r")
    end
    readable ? Machine.bytes("r+") : Machine.bytes("w")
  end

  # rb_io_open_descriptor: an IO of `klass` on the descriptor `fd`, with
  # the FMODE_* bits `fmode`, the path, the timeout and the encodings
  # that C gives (`encoding` may be NULL). As in ruby, the initialize of
  # `klass` does not run.
  #: (value, i32, i32, value, value, ptr) -> value
  def rb_io_open_descriptor(klass, fd, fmode, path, timeout, encoding)
    Machine.gates_enter
    zr_c_entered()
    external = Machine.value(QNIL)
    internal = Machine.value(QNIL)
    if encoding != 0
      # enc2 is the external encoding when the stream converts, and enc
      # the internal one; otherwise enc is the external one.
      if RbIoEnc[encoding].enc2 == 0
        external = zr_capi_enc_value(RbIoEnc[encoding].enc)
      else
        external = zr_capi_enc_value(RbIoEnc[encoding].enc2)
        internal = zr_capi_enc_value(RbIoEnc[encoding].enc)
      end
    end
    args = Machine.slot(56)
    Machine.store64(args, 0, Machine.word(klass))
    Machine.store64(args, 8, Machine.word(zr_fix(Machine.sword(fd))))
    Machine.store64(args, 16, Machine.word(zr_fix(Machine.sword(fmode))))
    Machine.store64(args, 24, Machine.word(path))
    Machine.store64(args, 32, Machine.word(timeout))
    Machine.store64(args, 40, Machine.word(external))
    Machine.store64(args, 48, Machine.word(internal))
    zr_c_result(zr_send(zr_core_class(Machine.id(:IO)), Machine.id(:c_open_descriptor), 7, args))
  end

  # The Encoding of an rb_encoding, or nil for NULL.
  #: (ptr) -> value
  def zr_capi_enc_value(enc)
    enc == 0 ? Machine.value(QNIL) : zr_capi_encoding_object(zr_capi_enc_index(enc))
  end

  # The rb_encoding of an Encoding, or NULL for nil.
  #: (value) -> ptr
  def zr_capi_enc_of(encoding)
    if encoding == QNIL
      return Machine.ptr(0)
    end
    zr_capi_encoding(zr_fix2long(zr_c_result(zr_send(encoding, Machine.id(:index), 0, Machine.ptr(0)))))
  end
end
