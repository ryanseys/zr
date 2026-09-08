# Kernel: puts.

# One line for `v`: its bytes when it is a String, else its `to_s`, and
# a newline unless the bytes end in one.
sig [Value] => Void
machine def zr_puts_value(v)
  s = v
  if zr_type(v) != T_STRING
    s = zr_send(v, Machine.id(:to_s), 0, 0)
  end
  len = RString.len(s)
  ptr = RString.ptr(s)
  zr_write_out(ptr, len)
  if len == 0 || Machine.load8(ptr + len - 1, 0) != 10
    zr_write_out(Machine.bytes("\n"), 1)
  end
end

sig [Value, Word, Ptr] => Value
machine def zr_puts(recv, argc, argv)
  if argc == 0
    zr_write_out(Machine.bytes("\n"), 1)
  end
  i = 0
  while i < argc
    zr_puts_value(Machine.value(Machine.load64(argv + (i * 8), 0)))
    i += 1
  end
  Machine.value(QNIL)
end

sig [Value, Word, Ptr] => Value
machine def zr_nil_to_s(recv, argc, argv)
  zr_str_new(Machine.bytes(""), 0)
end

sig [Value, Word, Ptr] => Value
machine def zr_true_to_s(recv, argc, argv)
  zr_str_new(Machine.bytes("true"), 4)
end

sig [Value, Word, Ptr] => Value
machine def zr_false_to_s(recv, argc, argv)
  zr_str_new(Machine.bytes("false"), 5)
end

# `#<Name:0x` and sixteen hex digits of the address, as CRuby prints;
# the main object prints as `main`.
sig [Value, Word, Ptr] => Value
machine def zr_obj_to_s(recv, argc, argv)
  if recv == zr_global(G_MAIN)
    return zr_str_new(Machine.bytes("main"), 4)
  end
  buf = Machine.slot(64)
  id = RClass.name(zr_class_of(recv))
  n = zr_symbol_name_len(id)
  Machine.store8(buf, 0, Machine.i8(35))
  Machine.store8(buf, 1, Machine.i8(60))
  zr_memcpy(buf + 2, zr_symbol_name_ptr(id), n)
  at = n + 2
  Machine.store8(buf + at, 0, Machine.i8(58))
  Machine.store8(buf + at, 1, Machine.i8(48))
  Machine.store8(buf + at, 2, Machine.i8(120))
  at += 3
  w = Machine.word(recv)
  i = 0
  while i < 16
    d = (w >> (60 - (i * 4))) & 15
    if d < 10
      Machine.store8(buf + at + i, 0, Machine.i8(48 + d))
    else
      Machine.store8(buf + at + i, 0, Machine.i8(87 + d))
    end
    i += 1
  end
  at += 16
  Machine.store8(buf + at, 0, Machine.i8(62))
  zr_str_new(buf, at + 1)
end
