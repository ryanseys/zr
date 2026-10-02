# Kernel: puts.

module Zr::Kern
  # Writes one line for `v`: its bytes if it is a String, else its `to_s`.
  # It adds a newline if the bytes do not end in one.
  sig [Value] => Value
  def zr_puts_value(v)
    if zr_type(v) == T_ARRAY
      i = 0
      while i < RArray.len(v)
        r = zr_puts_value(zr_ary_at(v, i))
        return r if r == QUNDEF
        i += 1
      end
      return Machine.value(QNIL)
    end
    s = v
    if zr_type(v) != T_STRING
      s = zr_obj_as_string(v)
      return s if s == QUNDEF
    end
    len = RString.len(s)
    ptr = RString.ptr(s)
    zr_write_out(ptr, len)
    if len == 0 || Machine.load8(ptr + len - 1, 0) != 10
      zr_write_out(Machine.bytes("\n"), 1)
    end
    Machine.value(QNIL)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_puts(recv, argc, argv, cref, blk)
    if argc == 0
      zr_write_out(Machine.bytes("\n"), 1)
    end
    i = 0
    while i < argc
      r = zr_puts_value(Machine.value(Machine.load64(argv + (i * 8), 0)))
      return r if r == QUNDEF
      i += 1
    end
    Machine.value(QNIL)
  end

  # `print`: writes the `to_s` of each argument, with nothing between or
  # after them.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_print(recv, argc, argv, cref, blk)
    i = 0
    while i < argc
      v = Machine.value(Machine.load64(argv + (i * 8), 0))
      s = v
      if zr_type(v) != T_STRING
        s = zr_obj_as_string(v)
        return s if s == QUNDEF
      end
      zr_write_out(RString.ptr(s), RString.len(s))
      i += 1
    end
    Machine.value(QNIL)
  end

  G_NIL_TO_S = 55
  G_TRUE_TO_S = 56
  G_FALSE_TO_S = 57

  # The single frozen US-ASCII String that `nil.to_s`, `true.to_s` or
  # `false.to_s` always returns. The first call makes it.
  sig [Word, Ptr, Word] => Value
  def zr_fixed_name(g, bytes, len)
    s = zr_global(g)
    if zr_special_p(s)
      s = zr_usascii_str_new(bytes, len)
      RBasic.set_flags(s, RBasic.flags(s) | FL_FREEZE)
      zr_set_global(g, s)
    end
    s
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_nil_to_s(recv, argc, argv, cref, blk)
    zr_fixed_name(G_NIL_TO_S, Machine.bytes(""), 0)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_true_to_s(recv, argc, argv, cref, blk)
    zr_fixed_name(G_TRUE_TO_S, Machine.bytes("true"), 4)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_false_to_s(recv, argc, argv, cref, blk)
    zr_fixed_name(G_FALSE_TO_S, Machine.bytes("false"), 5)
  end

  # `#<Name:0x` and sixteen hex digits of the address, as CRuby prints.
  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_to_s(recv, argc, argv, cref, blk)
    zr_any_to_s(recv)
  end

  sig [Value, Word, Ptr, Value, Value] => Value
  def zr_obj_not(recv, argc, argv, cref, blk)
    zr_bool(recv == QNIL || recv == QFALSE)
  end

  # Writes the String `s` to `$stderr`, as CRuby's rb_write_error2 does.
  # While `$stderr` is STDERR, it writes to fd 2. Else it calls `write`.
  # If that `write` raises, it writes the bytes to fd 2.
  sig [Value] => Void
  def zr_write_stderr(s)
    out = zr_gvar_get(Machine.id(:$stderr))
    if zr_special_p(out) || out == zr_core_class(Machine.id(:STDERR))
      zr_write_err(RString.ptr(s), RString.len(s))
      return
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(s))
    r = zr_send(out, Machine.id(:write), 1, slot)
    if r == QUNDEF
      Task.set_pending(zr_task(), Machine.value(QNIL))
      zr_write_err(RString.ptr(s), RString.len(s))
    end
  end

  # Writes a line on stderr: the output of `warn`.
  sig [Value] => Value
  def zr_warn_line(s)
    zr_write_stderr(s)
    zr_write_stderr(zr_str_new(Machine.bytes("\n"), 1))
    Machine.value(QNIL)
  end

  # `rb_warn`: writes `file:line: warning: message` on stderr, with the
  # nearest frame that has a file. It writes nothing if `$VERBOSE` is nil.
  sig [Ptr, Word] => Void
  def zr_warn_here(bytes, n)
    if zr_gvar_get(Machine.id(:$VERBOSE)) == QNIL
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    rec = zr_frame_with_file(Task.top(zr_task()))
    if rec != 0
      meta = Frame.meta(rec)
      zr_buf_push(b, FrameMeta.file(meta), FrameMeta.file_len(meta))
      zr_buf_byte(b, 58)
      zr_buf_long(b, zr_frame_line(rec))
      zr_buf_push(b, Machine.bytes(": "), 2)
    end
    zr_buf_push(b, Machine.bytes("warning: "), 9)
    zr_buf_push(b, bytes, n)
    zr_buf_byte(b, 10)
    zr_warning_write(zr_buf_take(b))
  end

  # rb_write_warning_str: a warning goes to `Warning.warn`, which a program
  # may override to catch it. Before the program starts, and while
  # `Warning.warn` runs, it goes straight to stderr.
  sig [Value] => Void
  def zr_warning_write(s)
    depth = Machine.static(:warning_depth, 8)
    if !zr_program_started_p() || Machine.load64(depth, 0) != 0
      zr_write_stderr(s)
      return
    end
    Machine.store64(depth, 0, 1)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(s))
    zr_send(zr_const_get_at(zr_global(G_OBJECT), Machine.id(:Warning)), Machine.id(:warn), 1, slot)
    Machine.store64(depth, 0, 0)
  end

  # The core library's `rb_warn`.
  # Returns `file:line: ` for the program frame that caused a warning, or
  # an empty String if only runtime frames are on the stack.
  sig [] => Value
  def zr_warn_position
    rec = zr_frame_with_file(Task.top(zr_task()))
    if rec == 0
      return zr_str_new(0, 0)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    meta = Frame.meta(rec)
    zr_buf_push(b, FrameMeta.file(meta), FrameMeta.file_len(meta))
    zr_buf_byte(b, 58)
    zr_buf_long(b, zr_frame_line(rec))
    zr_buf_push(b, Machine.bytes(": "), 2)
    zr_buf_take(b)
  end

  sig [Value] => Value
  def zr_warn_here_m(s)
    zr_warn_here(RString.ptr(s), RString.len(s))
    Machine.value(QNIL)
  end

  # `#<Thread:0x...` without the closing bracket, for an inspect that
  # adds more.
  sig [Value] => Value
  def zr_obj_head(recv)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_obj_head(b, recv)
    zr_buf_take_at(b, ENC_BINARY)
  end

  sig [Value] => Value
  def zr_special_p_m(v)
    zr_bool(zr_special_p(v))
  end
end
