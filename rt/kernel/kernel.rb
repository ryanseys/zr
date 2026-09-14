# Kernel: puts.

# One line for `v`: its bytes when it is a String, else its `to_s`, and
# a newline unless the bytes end in one.
sig [Value] => Value
machine def zr_puts_value(v)
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
machine def zr_puts(recv, argc, argv, cref, blk)
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

# `print`: each argument's `to_s`, nothing between or after.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_print(recv, argc, argv, cref, blk)
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

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_nil_to_s(recv, argc, argv, cref, blk)
  zr_str_new(Machine.bytes(""), 0)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_true_to_s(recv, argc, argv, cref, blk)
  zr_str_new(Machine.bytes("true"), 4)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_false_to_s(recv, argc, argv, cref, blk)
  zr_str_new(Machine.bytes("false"), 5)
end

# `#<Name:0x` and sixteen hex digits of the address, as CRuby prints.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_to_s(recv, argc, argv, cref, blk)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_obj_head(b, recv)
  zr_buf_byte(b, 62)
  zr_buf_take(b)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_not(recv, argc, argv, cref, blk)
  zr_bool(recv == QNIL || recv == QFALSE)
end

# The String `s` for `$stderr`, as CRuby's rb_write_error2 writes it:
# on fd 2 while `$stderr` is STDERR, else through its `write`. A
# `write` that raises leaves the bytes on fd 2 instead.
sig [Value] => Void
machine def zr_write_stderr(s)
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

# A line on stderr: `warn`'s output.
sig [Value] => Value
machine def zr_warn_line(s)
  zr_write_stderr(s)
  zr_write_stderr(zr_str_new(Machine.bytes("\n"), 1))
  Machine.value(QNIL)
end

# `rb_warn`: `file:line: warning: message` on stderr, naming the
# nearest frame with a file, unless `$VERBOSE` is nil.
sig [Ptr, Word] => Void
machine def zr_warn_here(bytes, n)
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
    zr_buf_long(b, Frame.line(rec))
    zr_buf_push(b, Machine.bytes(": "), 2)
  end
  zr_buf_push(b, Machine.bytes("warning: "), 9)
  zr_buf_push(b, bytes, n)
  zr_buf_byte(b, 10)
  zr_write_stderr(zr_buf_take(b))
end

# The core's `rb_warn`.
# `file:line: ` for the program frame a warning came from, or empty
# where the runtime itself is the only frame.
sig [] => Value
machine def zr_warn_position
  rec = zr_frame_with_file(Task.top(zr_task()))
  if rec == 0
    return zr_str_new(0, 0)
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  meta = Frame.meta(rec)
  zr_buf_push(b, FrameMeta.file(meta), FrameMeta.file_len(meta))
  zr_buf_byte(b, 58)
  zr_buf_long(b, Frame.line(rec))
  zr_buf_push(b, Machine.bytes(": "), 2)
  zr_buf_take(b)
end

sig [Value] => Value
machine def zr_warn_here_m(s)
  zr_warn_here(RString.ptr(s), RString.len(s))
  Machine.value(QNIL)
end

# `#<Thread:0x...` without the closing bracket, for an inspect that
# adds more.
sig [Value] => Value
machine def zr_obj_head(recv)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_obj_head(b, recv)
  zr_buf_take(b)
end

sig [Value] => Value
machine def zr_special_p_m(v)
  zr_bool(zr_special_p(v))
end
