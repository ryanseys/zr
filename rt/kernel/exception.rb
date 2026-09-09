# Exceptions and the signal protocol. A function that can raise answers
# a Value, and `undef` means the exception is in the task's pending
# slot; every call site tests for it and leaves through its landing
# block. An exception captures the frame chain when it is raised; the
# report prints it as CRuby does.
#
# Every frame record carries a FrameMeta: what the backtrace prints for
# it. A builtin method's frame is pushed by dispatch and borrows the
# file and line of the nearest Ruby frame outside it.
Machine.struct :FrameMeta, name: Word, owner: Value, file: Ptr, file_len: Word, kind: Word, line: Word, parent: Ptr, arity: Word, params: Ptr, fn: Ptr
KIND_MAIN = 0
KIND_DEF = 1
KIND_BUILTIN = 2
KIND_CLASS = 3
KIND_MODULE = 4
KIND_BLOCK = 5
KIND_SCLASS = 6
# A frame of the runtime's own Ruby (a block in a builtin written in
# Ruby): no row in a backtrace.
KIND_HIDDEN = 7

Machine.struct :BtRow, meta: Ptr, file: Ptr, file_len: Word, line: Word
# `bt` is a backtrace the program set, else nil and the captured rows
# stand; `cause` is undef until the raise decides it.
Machine.struct :RException, basic: RBasic, message: Value, rows: Ptr, nrows: Word, bt: Value, cause: Value
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
  while rec != 0 && (FrameMeta.kind(Frame.meta(rec)) == KIND_BUILTIN || FrameMeta.kind(Frame.meta(rec)) == KIND_HIDDEN)
    rec = Frame.prev(rec)
  end
  rec
end

# One row per frame from `top` outward, into a fresh buffer.
sig [Value, Ptr] => Void
machine def zr_backtrace_capture(exc, top)
  n = 0
  rec = top
  while rec != 0
    if FrameMeta.kind(Frame.meta(rec)) != KIND_HIDDEN
      n += 1
    end
    rec = Frame.prev(rec)
  end
  rows = malloc(n * BtRow.size)
  i = 0
  rec = top
  while rec != 0
    meta = Frame.meta(rec)
    if FrameMeta.kind(meta) != KIND_HIDDEN
      row = rows + (i * BtRow.size)
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
    end
    rec = Frame.prev(rec)
  end
  RException.set_rows(exc, rows)
  RException.set_nrows(exc, n)
end

sig [Value, Value] => Value
machine def zr_exc_new(klass, message)
  e = zr_alloc(T_EXCEPTION, klass)
  RException.set_message(e, message)
  RException.set_rows(e, 0)
  RException.set_nrows(e, 0)
  RException.set_bt(e, Machine.value(QNIL))
  RException.set_cause(e, Machine.value(QUNDEF))
  e
end

# Raise `exc` from the frame `top`: the backtrace is captured here
# unless the exception has one, the exception parked in the task, and
# `undef` answered for the caller to pass on.
sig [Value, Ptr] => Value
machine def zr_raise_from(exc, top)
  if RException.rows(exc) == 0 && RException.bt(exc) == QNIL
    zr_backtrace_capture(exc, top)
  end
  if RException.bt(exc) != QNIL && RException.rows(exc) != 0
    free(RException.rows(exc))
    RException.set_rows(exc, 0)
    RException.set_nrows(exc, 0)
  end
  t = zr_task()
  if RException.cause(exc) == QUNDEF
    cause = Task.errinfo(t)
    RException.set_cause(exc, cause == exc ? Machine.value(QNIL) : cause)
  end
  Task.set_pending_kind(t, PENDING_RAISE)
  Task.set_pending(t, exc)
  Machine.value(QUNDEF)
end

sig [Value] => Value
machine def zr_raise(exc)
  zr_raise_from(exc, Task.top(zr_task()))
end

# In a landing block with a rescue clause: the pending exception when
# the signal is a raise, else undef (a break or return passes through).
sig [] => Value
machine def zr_rescuable
  t = zr_task()
  if Task.pending_kind(t) == PENDING_RAISE
    return Task.pending(t)
  end
  Machine.value(QUNDEF)
end

# Whether a rescue clause naming `klass` takes `exc`.
sig [Value, Value] => Value
machine def zr_exc_match(exc, klass)
  t = zr_type(klass)
  unless t == T_CLASS || t == T_MODULE
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("class or module required for rescue clause"), 42)
  end
  zr_bool(zr_is_a(exc, klass))
end

# `rescue *list`: whether any class in the Array takes `exc`.
sig [Value, Value] => Value
machine def zr_exc_match_any(exc, list)
  if zr_special_p(list) || zr_type(list) != T_ARRAY
    return zr_exc_match(exc, list)
  end
  i = 0
  while i < RArray.len(list)
    r = zr_exc_match(exc, zr_ary_at(list, i))
    return r if r == QUNDEF
    if r == QTRUE
      return r
    end
    i += 1
  end
  Machine.value(QFALSE)
end

# `when *list`: whether any element answers `=== subject` truthily.
sig [Value, Value] => Value
machine def zr_case_any(subject, list)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(subject))
  if zr_special_p(list) || zr_type(list) != T_ARRAY
    return zr_send(list, Machine.id(:===), 1, slot)
  end
  i = 0
  while i < RArray.len(list)
    r = zr_send(zr_ary_at(list, i), Machine.id(:===), 1, slot)
    return r if r == QUNDEF
    if r != QNIL && r != QFALSE
      return r
    end
    i += 1
  end
  Machine.value(QFALSE)
end

# `when *list` with no subject: whether any of the candidates is
# truthy; a plain value is the one candidate, nil none.
sig [Value] => Value
machine def zr_any_truthy(list)
  if zr_special_p(list) || zr_type(list) != T_ARRAY
    return zr_bool(list != QNIL && list != QFALSE)
  end
  i = 0
  while i < RArray.len(list)
    v = zr_ary_at(list, i)
    if v != QNIL && v != QFALSE
      return Machine.value(QTRUE)
    end
    i += 1
  end
  Machine.value(QFALSE)
end

# Entering a rescue clause: the exception leaves the pending slot and
# becomes `$!`. The previous `$!` is answered, for the clause's end.
sig [] => Value
machine def zr_rescue_enter
  t = zr_task()
  prev = Task.errinfo(t)
  Task.set_errinfo(t, Task.pending(t))
  Task.set_pending(t, Machine.value(QNIL))
  prev
end

sig [] => Value
machine def zr_errinfo
  Task.errinfo(zr_task())
end

sig [Value] => Void
machine def zr_errinfo_set(v)
  Task.set_errinfo(zr_task(), v)
end

# An ensure body runs with the signal set aside: the pending value is
# answered, for the caller's record, and the kind, home and site go to
# `out`, three words. A raise stays visible as `$!` meanwhile.
sig [Ptr] => Value
machine def zr_signal_take(out)
  t = zr_task()
  v = Task.pending(t)
  Machine.store64(out, 0, Task.pending_kind(t))
  Machine.store64(out, 8, Task.pending_home(t))
  Machine.store64(out, 16, Task.pending_site(t))
  if Task.pending_kind(t) == PENDING_RAISE
    Task.set_errinfo(t, v)
  end
  Task.set_pending(t, Machine.value(QNIL))
  Task.set_pending_kind(t, PENDING_RAISE)
  v
end

sig [Value, Ptr] => Value
machine def zr_signal_restore(v, out)
  zr_signal(Machine.load64(out, 0), v, Machine.ptr(Machine.load64(out, 8)), Machine.load64(out, 16))
end

# `Kernel#raise`: `$!` again with no arguments; a String makes a
# RuntimeError; a class is sent `new` with the message; an exception is
# raised as it is. The frame of `raise` itself is not in the backtrace.
# `Kernel#raise`: nothing re-raises `$!`; a String is a RuntimeError;
# anything else answers `exception` with the message, as a class does
# through `new`; a third argument is the backtrace; `cause:` sets the
# cause, else `$!` is.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_raise(recv, argc, argv, cref, blk)
  top = Frame.prev(Task.top(zr_task()))
  cause = Machine.value(QUNDEF)
  if zr_kw_take() != 0
    opts = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    argc -= 1
    known = Machine.slot(8)
    Machine.store64(known, 0, Machine.id(:cause))
    r = zr_kw_unknown(opts, known, 1)
    return r if r == QUNDEF
    cause = zr_hash_lookup(opts, zr_sym(Machine.id(:cause)))
    if cause != QUNDEF && cause != QNIL && (zr_special_p(cause) || zr_type(cause) != T_EXCEPTION)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception object expected"), 25)
    end
  end
  if argc == 0
    e = Task.errinfo(zr_task())
    if e == QNIL
      e = zr_exc_new(zr_global(G_RUNTIME_ERROR), zr_str_new(Machine.bytes(""), 0))
    end
  else
    if argc > 3
      return zr_wrong_arity_range(argc, 0, 3)
    end
    first = Machine.value(Machine.load64(argv, 0))
    if !zr_special_p(first) && zr_type(first) == T_STRING && argc == 1
      e = zr_exc_new(zr_global(G_RUNTIME_ERROR), first)
    else
      if zr_find_method(zr_class_of(first), Machine.id(:exception)) == 0
        return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception class/object expected"), 31)
      end
      e = zr_send(first, Machine.id(:exception), argc > 1 ? 1 : 0, argv + 8)
      return e if e == QUNDEF
      if zr_special_p(e) || zr_type(e) != T_EXCEPTION
        return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception object expected"), 25)
      end
    end
    if argc == 3
      r = zr_exc_set_backtrace_value(e, Machine.value(Machine.load64(argv, 16)))
      return r if r == QUNDEF
    end
  end
  if cause != QUNDEF
    RException.set_cause(e, cause)
  end
  zr_raise_from(e, top)
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

# `block in label`, or `block (N levels) in label` for a nested block.
sig [Ptr, Ptr] => Void
machine def zr_buf_label(b, meta)
  if FrameMeta.kind(meta) == KIND_BLOCK
    levels = 1
    outer = FrameMeta.parent(meta)
    while FrameMeta.kind(outer) == KIND_BLOCK
      levels += 1
      outer = FrameMeta.parent(outer)
    end
    zr_buf_push(b, Machine.bytes("block "), 6)
    if levels > 1
      zr_buf_byte(b, 40)
      zr_buf_long(b, levels)
      zr_buf_push(b, Machine.bytes(" levels) "), 9)
    end
    zr_buf_push(b, Machine.bytes("in "), 3)
    zr_buf_label(b, outer)
  elsif FrameMeta.kind(meta) == KIND_MAIN
    zr_buf_push(b, Machine.bytes("<main>"), 6)
  elsif FrameMeta.kind(meta) == KIND_SCLASS
    zr_buf_push(b, Machine.bytes("singleton class"), 15)
  elsif FrameMeta.kind(meta) == KIND_CLASS || FrameMeta.kind(meta) == KIND_MODULE
    zr_buf_push(b, FrameMeta.kind(meta) == KIND_CLASS ? Machine.bytes("<class:") : Machine.bytes("<module:"), FrameMeta.kind(meta) == KIND_CLASS ? 7 : 8)
    zr_buf_sym(b, FrameMeta.name(meta))
    zr_buf_byte(b, 62)
  else
    zr_buf_method_label(b, FrameMeta.owner(meta), FrameMeta.name(meta))
  end
end

# `Owner#name`; `Owner.name` for a class's singleton method; the name
# alone for an object's singleton method or an anonymous owner.
sig [Ptr, Value, Word] => Void
machine def zr_buf_method_label(b, owner, name)
  if zr_type(owner) == T_ICLASS
    owner = RClass.attached(owner)
  end
  if zr_singleton_p(owner)
    attached = RClass.attached(owner)
    t = zr_type(attached)
    if (t == T_CLASS || t == T_MODULE) && RClass.name(attached) != QNIL
      zr_buf_str(b, RClass.name(attached))
      zr_buf_byte(b, 46)
    end
  elsif RClass.name(owner) != QNIL
    zr_buf_str(b, RClass.name(owner))
    zr_buf_byte(b, 35)
  end
  zr_buf_sym(b, name)
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

# `Exception#backtrace`: one `file:line:in 'label'` String per row, or
# nil before the exception is raised.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_backtrace(recv, argc, argv, cref, blk)
  if RException.bt(recv) != QNIL
    return RException.bt(recv)
  end
  rows = RException.rows(recv)
  if rows == 0
    return Machine.value(QNIL)
  end
  n = RException.nrows(recv)
  out = zr_ary_new(n)
  i = 0
  while i < n
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_row(b, rows + (i * BtRow.size))
    zr_ary_push(out, zr_buf_take(b))
    i += 1
  end
  out
end

# An uncaught exception on stderr, as CRuby prints it, then exit 1.
sig [Value] => Void
machine def zr_report(exc)
  zr_error_print(exc)
  exit(1)
end

# An exception on stderr: the exception's own `detailed_message` after
# the first row. A SystemStackError past 18 rows shows the first 9 and
# the last 4, with the count of the levels between.
sig [Value] => Void
machine def zr_error_print(exc)
  detail = zr_send(exc, Machine.id(:detailed_message), 0, 0)
  if detail == QUNDEF || zr_special_p(detail) || zr_type(detail) != T_STRING
    detail = zr_class_name_of(exc)
    Task.set_pending(zr_task(), Machine.value(QNIL))
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  rows = RException.rows(exc)
  n = RException.nrows(exc)
  if n == 0
    zr_buf_str(b, detail)
    zr_buf_byte(b, 10)
  end
  skip_at = 0 - 1
  if zr_class_of(exc) == zr_global(G_SYSTEM_STACK_ERROR) && n > 18
    skip_at = 9
  end
  i = 0
  while i < n
    if i == skip_at
      zr_buf_push(b, Machine.bytes("\t ... "), 6)
      zr_buf_long(b, n - 13)
      zr_buf_push(b, Machine.bytes(" levels...\n"), 11)
      i += n - 13
    end
    row = rows + (i * BtRow.size)
    if i == 0
      zr_buf_row(b, row)
      zr_buf_push(b, Machine.bytes(": "), 2)
      zr_buf_str(b, detail)
      zr_buf_byte(b, 10)
    else
      zr_buf_push(b, Machine.bytes("\tfrom "), 6)
      zr_buf_row(b, row)
      zr_buf_byte(b, 10)
    end
    i += 1
  end
  zr_write_err(Buf.ptr(b), Buf.len(b))
  free(Buf.ptr(b))
end

G_SYSTEM_STACK_ERROR = 35

# A Ruby frame about to start below the task's stack limit.
sig [] => Value
machine def zr_stack_overflow
  zr_raise_msg(zr_global(G_SYSTEM_STACK_ERROR), Machine.bytes("stack level too deep"), 20)
end

# `set_backtrace`: an Array of Strings, one String, or nil.
sig [Value, Value] => Value
machine def zr_exc_set_backtrace_value(exc, bt)
  if bt == QNIL
    RException.set_bt(exc, bt)
    return bt
  end
  if !zr_special_p(bt) && zr_type(bt) == T_STRING
    a = zr_ary_new(1)
    zr_ary_push(a, bt)
    bt = a
  end
  if zr_special_p(bt) || zr_type(bt) != T_ARRAY
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("backtrace must be an Array of String or an Array of Thread::Backtrace::Location"), 79)
  end
  i = 0
  while i < RArray.len(bt)
    v = zr_ary_at(bt, i)
    if zr_special_p(v) || zr_type(v) != T_STRING
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("backtrace must be an Array of String or an Array of Thread::Backtrace::Location"), 79)
    end
    i += 1
  end
  RException.set_bt(exc, bt)
  bt
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_set_backtrace(recv, argc, argv, cref, blk)
  zr_exc_set_backtrace_value(recv, Machine.value(Machine.load64(argv, 0)))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_cause(recv, argc, argv, cref, blk)
  c = RException.cause(recv)
  if c == QUNDEF
    return Machine.value(QNIL)
  end
  c
end

# An exception's details as the program reads them: `NameError#name`
# and the like live in ivars the raise sets.
sig [Value, Word, Value] => Void
machine def zr_exc_detail(exc, id, v)
  zr_ivar_set(exc, id, v)
end

# `file:line:in 'label'` for the live frame `rec`.
sig [Ptr, Ptr] => Void
machine def zr_buf_frame(b, rec)
  source = zr_frame_with_file(rec)
  if source != 0
    zr_buf_push(b, FrameMeta.file(Frame.meta(source)), FrameMeta.file_len(Frame.meta(source)))
    zr_buf_byte(b, 58)
    zr_buf_long(b, Frame.line(source))
  end
  zr_buf_push(b, Machine.bytes(":in '"), 5)
  zr_buf_label(b, Frame.meta(rec))
  zr_buf_byte(b, 39)
end

# `Kernel#caller(start = 1, length = nil)`: the rows outward from the
# caller's frame, the first `start` of them skipped.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_caller(recv, argc, argv, cref, blk)
  if argc > 2
    return zr_wrong_arity_range(argc, 0, 2)
  end
  start = 1
  limit = 0 - 1
  if argc > 0
    start = zr_fix2long(Machine.value(Machine.load64(argv, 0)))
    if start < 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("negative level ("), 16)
      zr_buf_long(b, start)
      zr_buf_byte(b, 41)
      return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
    end
  end
  if argc > 1 && Machine.value(Machine.load64(argv, 8)) != QNIL
    limit = zr_fix2long(Machine.value(Machine.load64(argv, 8)))
    if limit < 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("negative size ("), 15)
      zr_buf_long(b, limit)
      zr_buf_byte(b, 41)
      return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
    end
  end
  out = zr_ary_new(8)
  rec = Frame.prev(Task.top(zr_task()))
  while rec != 0 && (limit < 0 || RArray.len(out) < limit)
    if FrameMeta.kind(Frame.meta(rec)) != KIND_HIDDEN
      if start > 0
        start -= 1
      else
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_frame(b, rec)
        zr_ary_push(out, zr_buf_take(b))
      end
    end
    rec = Frame.prev(rec)
  end
  if start > 0
    return Machine.value(QNIL)
  end
  out
end
