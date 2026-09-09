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
    if RArray.len(v) == 0
      zr_write_out(Machine.bytes("\n"), 1)
    end
    return Machine.value(QNIL)
  end
  s = v
  if zr_type(v) != T_STRING
    s = zr_send(v, Machine.id(:to_s), 0, 0)
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
      s = zr_send(v, Machine.id(:to_s), 0, 0)
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

# A line on stderr: `warn`'s output.
sig [Value] => Value
machine def zr_warn_line(s)
  zr_write_err(RString.ptr(s), RString.len(s))
  zr_write_err(Machine.bytes("\n"), 1)
  Machine.value(QNIL)
end
