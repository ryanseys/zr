# Dispatch: the receiver's class chain, then the call through the
# entry's code pointer. A miss is a NoMethodError.

sig [Value] => Void
machine def zr_write_class_name(klass)
  id = RClass.name(klass)
  zr_write_err(zr_symbol_name_ptr(id), zr_symbol_name_len(id))
end

# CRuby's message, without the backtrace line that exceptions will add.
# A bare identifier (`vcall`) is a NameError, and names main as `main`.
sig [Value, Word, Bool] => Void
machine def zr_no_method(recv, mid, vcall)
  if vcall
    zr_write_err(Machine.bytes("undefined local variable or method '"), 36)
  else
    zr_write_err(Machine.bytes("undefined method '"), 18)
  end
  zr_write_err(zr_symbol_name_ptr(mid), zr_symbol_name_len(mid))
  zr_write_err(Machine.bytes("' for "), 6)
  if recv == zr_global(G_MAIN)
    if vcall
      zr_write_err(Machine.bytes("main"), 4)
    else
      zr_write_err(Machine.bytes("main:Object"), 11)
    end
  elsif recv == QNIL
    zr_write_err(Machine.bytes("nil"), 3)
  elsif recv == QTRUE
    zr_write_err(Machine.bytes("true"), 4)
  elsif recv == QFALSE
    zr_write_err(Machine.bytes("false"), 5)
  else
    zr_write_err(Machine.bytes("an instance of "), 15)
    zr_write_class_name(zr_class_of(recv))
  end
  if vcall
    zr_write_err(Machine.bytes(" (NameError)\n"), 13)
  else
    zr_write_err(Machine.bytes(" (NoMethodError)\n"), 17)
  end
  exit(1)
end

sig [Word, Word] => Void
machine def zr_wrong_arity(given, expected)
  buf = Machine.slot(24)
  zr_write_err(Machine.bytes("wrong number of arguments (given "), 33)
  zr_write_err(buf, zr_long_digits(given, buf))
  zr_write_err(Machine.bytes(", expected "), 11)
  zr_write_err(buf, zr_long_digits(expected, buf))
  zr_write_err(Machine.bytes(") (ArgumentError)\n"), 18)
  exit(1)
end

# `argv` points at `argc` Values the caller keeps rooted.
sig [Value, Word, Word, Ptr, Bool] => Value
machine def zr_dispatch(recv, mid, argc, argv, vcall)
  e = zr_find_method(zr_class_of(recv), mid)
  if e == 0
    zr_no_method(recv, mid, vcall)
  end
  arity = MEntry.arity(e)
  if arity >= 0 && argc != arity
    zr_wrong_arity(argc, arity)
  end
  Machine.call(:method, MEntry.fn(e), recv, argc, argv)
end

sig [Value, Word, Word, Ptr] => Value
machine def zr_send(recv, mid, argc, argv)
  zr_dispatch(recv, mid, argc, argv, false)
end

# A bare identifier: the same dispatch, a NameError on a miss.
sig [Value, Word, Word, Ptr] => Value
machine def zr_vcall(recv, mid, argc, argv)
  zr_dispatch(recv, mid, argc, argv, true)
end
