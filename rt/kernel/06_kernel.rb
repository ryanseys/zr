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
