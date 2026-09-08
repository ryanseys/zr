# Exceptions and the signal protocol. A function that can raise answers
# a Value, and `undef` means the exception is in the task's pending
# slot; every call site tests for it and leaves through its landing
# block. An exception captures the frame chain when it is raised; the
# report prints it as CRuby does.
#
# Every frame record carries a FrameMeta: what the backtrace prints for
# it. A builtin method's frame is pushed by dispatch and borrows the
# file and line of the nearest Ruby frame outside it.
Machine.struct :FrameMeta, name: Word, owner: Value, file: Ptr, file_len: Word, kind: Word, line: Word
KIND_MAIN = 0
KIND_DEF = 1
KIND_BUILTIN = 2

Machine.struct :BtRow, meta: Ptr, file: Ptr, file_len: Word, line: Word
Machine.struct :RException, basic: RBasic, message: Value, rows: Ptr, nrows: Word
T_EXCEPTION = 24

G_EXCEPTION = 16
G_STANDARD_ERROR = 17
G_ARGUMENT_ERROR = 18
G_NAME_ERROR = 19
G_NO_METHOD_ERROR = 20
G_TYPE_ERROR = 21
G_ZERO_DIVISION_ERROR = 22
G_RUNTIME_ERROR = 23

# The nearest frame at or outside `rec` that has a file of its own.
sig [Ptr] => Ptr
machine def zr_frame_with_file(rec)
  while rec != 0 && FrameMeta.kind(Frame.meta(rec)) == KIND_BUILTIN
    rec = Frame.prev(rec)
  end
  rec
end

# One row per frame, innermost first, into a fresh buffer.
sig [Value] => Void
machine def zr_backtrace_capture(exc)
  n = 0
  rec = Task.top(zr_task())
  while rec != 0
    n += 1
    rec = Frame.prev(rec)
  end
  rows = malloc(n * BtRow.size)
  i = 0
  rec = Task.top(zr_task())
  while rec != 0
    row = rows + (i * BtRow.size)
    meta = Frame.meta(rec)
    BtRow.set_meta(row, meta)
    source = zr_frame_with_file(rec)
    if source == 0
      BtRow.set_file(row, 0)
      BtRow.set_file_len(row, 0)
      BtRow.set_line(row, 0)
    else
      BtRow.set_file(row, FrameMeta.file(Frame.meta(source)))
      BtRow.set_file_len(row, FrameMeta.file_len(Frame.meta(source)))
      BtRow.set_line(row, Frame.line(source))
    end
    i += 1
    rec = Frame.prev(rec)
  end
  RException.set_rows(exc, rows)
  RException.set_nrows(exc, n)
end

sig [Value, Value] => Value
machine def zr_exc_new(klass, message)
  e = zr_alloc(T_EXCEPTION, klass)
  RException.set_message(e, message)
  e
end

# Raise `exc`: the backtrace is captured here, the exception parked in
# the task, and `undef` answered for the caller to pass on.
sig [Value] => Value
machine def zr_raise(exc)
  if RException.rows(exc) == 0
    zr_backtrace_capture(exc)
  end
  Task.set_pending(zr_task(), exc)
  Machine.value(QUNDEF)
end

sig [Value, Ptr, Word] => Value
machine def zr_raise_msg(klass, bytes, len)
  zr_raise(zr_exc_new(klass, zr_str_new(bytes, len)))
end

# Raise with a message built in `b`, which is taken.
sig [Value, Ptr] => Value
machine def zr_raise_buf(klass, b)
  zr_raise(zr_exc_new(klass, zr_buf_take(b)))
end

sig [Ptr, Ptr] => Void
machine def zr_buf_label(b, meta)
  if FrameMeta.kind(meta) == KIND_MAIN
    zr_buf_push(b, Machine.bytes("<main>"), 6)
  else
    zr_buf_sym(b, RClass.name(FrameMeta.owner(meta)))
    zr_buf_byte(b, 35)
    zr_buf_sym(b, FrameMeta.name(meta))
  end
end

# `file:line:in 'label'` for one row.
sig [Ptr, Ptr] => Void
machine def zr_buf_row(b, row)
  zr_buf_push(b, BtRow.file(row), BtRow.file_len(row))
  zr_buf_byte(b, 58)
  zr_buf_long(b, BtRow.line(row))
  zr_buf_push(b, Machine.bytes(":in '"), 5)
  zr_buf_label(b, BtRow.meta(row))
  zr_buf_byte(b, 39)
end

# An uncaught exception on stderr, as CRuby prints it, then exit 1.
sig [Value] => Void
machine def zr_report(exc)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  rows = RException.rows(exc)
  n = RException.nrows(exc)
  i = 0
  while i < n
    row = rows + (i * BtRow.size)
    if i == 0
      zr_buf_row(b, row)
      zr_buf_push(b, Machine.bytes(": "), 2)
      zr_buf_str(b, RException.message(exc))
      zr_buf_push(b, Machine.bytes(" ("), 2)
      zr_buf_sym(b, RClass.name(zr_class_of(exc)))
      zr_buf_push(b, Machine.bytes(")\n"), 2)
    else
      zr_buf_push(b, Machine.bytes("\tfrom "), 6)
      zr_buf_row(b, row)
      zr_buf_byte(b, 10)
    end
    i += 1
  end
  zr_write_err(Buf.ptr(b), Buf.len(b))
  free(Buf.ptr(b))
  exit(1)
end
