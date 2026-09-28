# Exceptions and the pending unwind protocol. A function that can raise
# returns a Value. `undef` means that the exception is in the pending
# slot of the task. Each call site checks for `undef` and leaves through
# its landing block. A raise captures the frame list, and the report
# prints it as CRuby does.
#
# Each frame record has a FrameMeta, which gives what the backtrace
# prints for the frame. Dispatch pushes the frame of a builtin method,
# and that frame uses the file and line of the nearest Ruby frame
# outside it.
# `locals` gives the locals of the scope in slot order (the count, then
# one symbol id for each). `env` is 1 when the first slot of the record
# contains the Env that keeps them. An eval and a Binding read this.
# `box` is the Ruby::Box that the function belongs to, or nil for main.
# It makes the code in a box see the definitions of that box.
# `ruby` is 1 on a core def that CRuby itself writes in Ruby. Such a
# method returns its real parameters, where a C method returns `[[:rest]]`.
# `node` is the id of the prism node that defines the function. A frame
# that raises on entry reports it.
# `cover` is the def-site record of this scope plus one, in a program
# where Coverage measures methods, and 0 in all other programs. A
# definition from this scope takes that record, which gives the span
# that ruby reports for the method. It is here, where both a Proc and a
# method entry can read it, because `define_method` takes a block.
Machine.struct :FrameMeta, name: Word, owner: Value, file: Ptr, file_len: Word, kind: Word, line: Word, parent: Ptr, arity: Word, params: Ptr, fn: Ptr, locals: Ptr, env: Word, box: Value, ruby: Word, captures: Ptr, node: Word, hidden: Word, cover: Word
KIND_MAIN = 0
KIND_DEF = 1
KIND_BUILTIN = 2
KIND_CLASS = 3
KIND_MODULE = 4
KIND_BLOCK = 5
KIND_SCLASS = 6
# A frame of the runtime's own Ruby (a block in a builtin written in
# Ruby). It has no frame in a backtrace.
KIND_HIDDEN = 7
# The toplevel of a required file.
KIND_TOP = 8
# The toplevel of an eval. It shows the label of the frame that called
# eval: `parent` is the meta of that frame, written at the call.
KIND_EVAL = 9
# A snippet that a box ran. It shows its own label, not the label of
# its caller.
KIND_COMPILED = 10

# One backtrace frame. `node` is the id of the prism node that the line
# ran, or 0.
Machine.struct :BtRow, meta: Ptr, file: Ptr, file_len: Word, line: Word, node: Word
# `bt` is a backtrace that the program set, or nil to use the captured
# frames. `cause` is undef until the raise sets it.
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

# The label of a captured frame reads the owner of its method, so the
# frames keep those classes alive until the backtrace is printed or
# replaced.
sig [Value] => Void
machine def zr_mark_backtrace_rows(exc)
  rows = RException.rows(exc)
  i = 0
  while i < RException.nrows(exc)
    zr_mark(FrameMeta.owner(BtRow.meta(rows + (i * BtRow.size))))
    i += 1
  end
end

# The line word of a frame contains the line in its low half and the id
# of the prism node that runs in its high half.
sig [Ptr] => Word
machine def zr_frame_line(rec)
  Frame.line(rec) & 4294967295
end

sig [Ptr] => Word
machine def zr_frame_node_id(rec)
  Frame.line(rec) >> 32
end

# The nearest frame at or outside `rec` that has a file of its own.
sig [Ptr] => Ptr
machine def zr_frame_with_file(rec)
  while rec != 0 && (FrameMeta.kind(Frame.meta(rec)) == KIND_BUILTIN || FrameMeta.kind(Frame.meta(rec)) == KIND_HIDDEN)
    rec = Frame.prev(rec)
  end
  rec
end

# Whether `rec` shows in a backtrace. A private helper of the core
# library does not show. A builtin that a helper calls on a core value
# or on itself also does not show, because CRuby's C does that work with
# no frame. A builtin that a helper calls on another plain object shows,
# as the frame that rb_funcall pushes for it does.
sig [Ptr] => Bool
machine def zr_frame_shown_p(rec)
  kind = FrameMeta.kind(Frame.meta(rec))
  if kind == KIND_HIDDEN
    return false
  end
  helper = Frame.prev(rec)
  if kind != KIND_BUILTIN || helper == 0 || !zr_frame_helper_p(helper)
    return true
  end
  me = Frame.self(rec)
  !zr_special_p(me) && zr_type(me) == T_OBJECT && me != Frame.self(helper)
end

# Whether `rec` runs a helper: a hidden def, or a block written in one.
# A block of the core library is also hidden, and its parent refers to
# the def that contains it. A def has no parent.
sig [Ptr] => Bool
machine def zr_frame_helper_p(rec)
  meta = Frame.meta(rec)
  while FrameMeta.kind(meta) == KIND_HIDDEN && FrameMeta.parent(meta) != 0
    meta = FrameMeta.parent(meta)
  end
  FrameMeta.kind(meta) == KIND_HIDDEN
end

# Captures one backtrace frame for each visible frame from `top`
# outward. The new buffer has space for the full frame list, so the
# visibility check runs once, while the frames are filled, and not also
# in a first counting pass.
sig [Value, Ptr] => Void
machine def zr_backtrace_capture(exc, top)
  n = 0
  rec = top
  while rec != 0
    n += 1
    rec = Frame.prev(rec)
  end
  rows = zr_xmalloc(n * BtRow.size)
  i = 0
  rec = top
  while rec != 0
    if zr_frame_shown_p(rec)
      row = rows + (i * BtRow.size)
      BtRow.set_meta(row, zr_frame_label_meta(rec))
      source = zr_frame_with_file(rec)
      if source == 0
        BtRow.set_file(row, 0)
        BtRow.set_file_len(row, 0)
        BtRow.set_line(row, 0)
        BtRow.set_node(row, 0)
      else
        BtRow.set_file(row, FrameMeta.file(Frame.meta(source)))
        BtRow.set_file_len(row, FrameMeta.file_len(Frame.meta(source)))
        BtRow.set_line(row, zr_frame_line(source))
        BtRow.set_node(row, zr_frame_node_id(source))
      end
      i += 1
    end
    rec = Frame.prev(rec)
  end
  RException.set_rows(exc, rows)
  RException.set_nrows(exc, i)
  zr_write_barrier_all(exc)
end

sig [Value, Value] => Value
machine def zr_exc_new(klass, message)
  e = zr_alloc(T_EXCEPTION, klass, RException.size)
  RException.set_message(e, message)
  RException.set_rows(e, 0)
  RException.set_nrows(e, 0)
  RException.set_bt(e, Machine.value(QNIL))
  RException.set_cause(e, Machine.value(QUNDEF))
  e
end

# Raises `exc` from the frame `top`. It captures the backtrace if the
# exception has none, puts the exception in the pending slot of the
# task, and returns `undef` for the caller to pass on.
sig [Value, Ptr] => Value
machine def zr_raise_from(exc, top)
  if zr_frozen_p(exc)
    # setup_exception raises a copy of a frozen exception that has a
    # backtrace or a cause. One with neither goes as it is, with none.
    if RException.rows(exc) == 0 && RException.bt(exc) == QNIL && RException.cause(exc) == QUNDEF
      return zr_raise_as_is(exc, top)
    end
    exc = zr_send(exc, Machine.id(:dup), 0, 0)
    return exc if exc == QUNDEF
  end
  if RException.rows(exc) == 0 && RException.bt(exc) == QNIL
    zr_backtrace_capture(exc, top)
  end
  if RException.bt(exc) != QNIL && RException.rows(exc) != 0
    zr_xfree(RException.rows(exc))
    RException.set_rows(exc, 0)
    RException.set_nrows(exc, 0)
  end
  t = zr_task()
  if RException.cause(exc) == QUNDEF
    cause = Task.errinfo(t)
    r = zr_exc_check_cause(exc, cause)
    return r if r == QUNDEF
    RException.set_cause(exc, cause == exc ? Machine.value(QNIL) : cause)
  end
  zr_raise_as_is(exc, top)
end

# The end of a raise: the $DEBUG report, the `:raise` event, then the
# exception in the pending slot of the task.
sig [Value, Ptr] => Value
machine def zr_raise_as_is(exc, top)
  t = zr_task()
  debug = zr_gvar_get(Machine.id(:$DEBUG))
  if debug != QNIL && debug != QFALSE && !zr_is_a(exc, zr_core_class(Machine.id(:SystemExit)))
    # A backtrace set by hand, or none at all, does not tell where the
    # raise is.
    at = exc
    if RException.rows(exc) == 0
      at = zr_exc_new(zr_core_class(Machine.id(:Exception)), Machine.value(QNIL))
      zr_backtrace_capture(at, top)
    end
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(at))
    r = zr_send(exc, Machine.id(:debug_report), 1, arg)
    return r if r == QUNDEF
  end
  fired = zr_trace_raise(exc, top)
  return fired if fired == QUNDEF
  Task.set_pending_kind(t, PENDING_RAISE)
  Task.set_pending(t, exc)
  Machine.value(QUNDEF)
end

sig [Value] => Value
machine def zr_raise(exc)
  zr_raise_from(exc, Task.top(zr_task()))
end

# For a landing block with a rescue clause. Returns the pending
# exception when the pending unwind is a raise, else undef (a break or
# a return passes through).
sig [] => Value
machine def zr_rescuable
  t = zr_task()
  if Task.pending_kind(t) == PENDING_RAISE
    return Task.pending(t)
  end
  Machine.value(QUNDEF)
end

# Whether a rescue clause for `klass` catches `exc`.
sig [Value, Value] => Value
machine def zr_exc_match(exc, klass)
  if zr_special_p(klass) || (zr_type(klass) != T_CLASS && zr_type(klass) != T_MODULE)
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("class or module required for rescue clause"), 42)
  end
  e = zr_find_method(zr_box_view(zr_class_of(klass)), Machine.id(:===))
  if e != 0 && (FrameMeta.owner(MEntry.meta(e)) != zr_global(G_MODULE) || zr_trace_c_p())
    # The class defines its own `===`, so that method decides. A traced
    # `:c_call` sees Module#=== as ruby sends it.
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(exc))
    r = zr_send(klass, Machine.id(:===), 1, arg)
    return r if r == QUNDEF
    return zr_bool(r != QNIL && r != QFALSE)
  end
  zr_bool(zr_is_a(exc, klass))
end

# `rescue *list`: whether a class in the splat catches `exc`.
sig [Value, Value] => Value
machine def zr_exc_match_any(exc, list)
  list = zr_splat_to_a(list)
  return list if list == QUNDEF
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

# `when *list`: whether `=== subject` is truthy for an element.
sig [Value, Value] => Value
machine def zr_case_any(subject, list)
  list = zr_splat_to_a(list)
  return list if list == QUNDEF
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(subject))
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

# `when *list` with no subject: whether the splat contains a truthy
# element.
sig [Value] => Value
machine def zr_any_truthy(list)
  list = zr_splat_to_a(list)
  return list if list == QUNDEF
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

# Starts a rescue clause: the exception moves from the pending slot to
# `$!`. Returns the previous `$!`, for the end of the clause.
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

# An ensure body runs with the pending unwind set aside. Returns the
# pending value, for the caller to keep, and writes the kind, home and
# site to the three words at `out`. During the body, a raise stays
# visible as `$!`.
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

# `Kernel#raise`. With no arguments, it raises `$!` again. A String
# gives a RuntimeError. For all other values, it calls `exception` with
# the message (a class does this through `new`). A third argument is
# the backtrace. `cause:` sets the cause, else `$!` is the cause. The
# frame of `raise` itself is not in the backtrace.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_raise(recv, argc, argv, cref, blk)
  top = Frame.prev(Task.top(zr_task()))
  cause = Machine.value(QUNDEF)
  if zr_kw_take() != 0
    # `raise` uses `cause:` itself. It gives all other keywords to
    # `exception` as one Hash argument.
    opts = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    cause = zr_hash_lookup(opts, zr_sym(Machine.id(:cause)))
    if cause != QUNDEF && cause != QNIL && (zr_special_p(cause) || zr_type(cause) != T_EXCEPTION)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception object expected"), 25)
    end
    if cause != QUNDEF
      rest = zr_hash_new()
      zr_hash_update(rest, opts)
      zr_hash_delete_m(rest, zr_sym(Machine.id(:cause)))
      if RHash.live(rest) == 0
        argc -= 1
      else
        Machine.store64(argv + ((argc - 1) * 8), 0, Machine.word(rest))
      end
    end
  end
  if argc == 0
    if cause != QUNDEF
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("only cause is given with no arguments"), 37)
    end
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
    r = zr_exc_check_cause(e, cause)
    return r if r == QUNDEF
    RException.set_cause(e, cause == e ? Machine.value(QNIL) : cause)
  end
  zr_raise_from(e, top)
end

# Raises `circular causes` when `e` is in the cause list of `cause`.
# An exception that is its own cause gets no cause.
sig [Value, Value] => Value
machine def zr_exc_check_cause(e, cause)
  if cause == e
    return Machine.value(QNIL)
  end
  c = cause
  while c != QNIL && c != QUNDEF
    if c == e
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("circular causes"), 15)
    end
    c = RException.cause(c)
  end
  Machine.value(QNIL)
end

sig [Value, Ptr, Word] => Value
machine def zr_raise_msg(klass, bytes, len)
  zr_raise(zr_exc_new(klass, zr_str_new(bytes, len)))
end

# Raises with the message in `b`, and takes ownership of `b`.
sig [Value, Ptr] => Value
machine def zr_raise_buf(klass, b)
  zr_raise(zr_exc_new(klass, zr_buf_take(b)))
end

# Returns a class of the core library, found by its constant name.
sig [Word] => Value
machine def zr_core_class(id)
  e = zr_const_row_in(zr_global(G_OBJECT), id, false)
  if e == 0
    zr_bug(Machine.bytes("a core class is missing at boot\n"), 32)
  end
  CEntry.value(e)
end

# `block in label`, or `block (N levels) in label` for a nested block.
sig [Ptr, Ptr] => Void
machine def zr_buf_label(b, meta)
  zr_buf_label_as(b, meta, true)
end

# Writes the label. When `qualified`, a method label includes the
# owner, as in a backtrace. Otherwise it is the name only, as in an
# instruction sequence.
sig [Ptr, Ptr, Bool] => Void
machine def zr_buf_label_as(b, meta, qualified)
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
    zr_buf_label_as(b, outer, qualified)
  elsif FrameMeta.kind(meta) == KIND_MAIN
    zr_buf_push(b, Machine.bytes("<main>"), 6)
  elsif FrameMeta.kind(meta) == KIND_TOP
    zr_buf_push(b, Machine.bytes("<top (required)>"), 16)
  elsif FrameMeta.kind(meta) == KIND_EVAL
    zr_buf_label_as(b, FrameMeta.parent(meta), qualified)
  elsif FrameMeta.kind(meta) == KIND_COMPILED
    zr_buf_push(b, Machine.bytes("<compiled>"), 10)
  elsif FrameMeta.kind(meta) == KIND_SCLASS
    zr_buf_push(b, Machine.bytes("singleton class"), 15)
  elsif FrameMeta.kind(meta) == KIND_CLASS || FrameMeta.kind(meta) == KIND_MODULE
    zr_buf_push(b, FrameMeta.kind(meta) == KIND_CLASS ? Machine.bytes("<class:") : Machine.bytes("<module:"), FrameMeta.kind(meta) == KIND_CLASS ? 7 : 8)
    zr_buf_sym(b, FrameMeta.name(meta))
    zr_buf_byte(b, 62)
  elsif qualified
    zr_buf_method_label(b, FrameMeta.owner(meta), FrameMeta.name(meta))
  else
    zr_buf_sym(b, FrameMeta.name(meta))
  end
end

# Writes `Owner#name`, or `Owner.name` for a singleton method of a
# class, or the name only for a singleton method of an object or for an
# anonymous owner.
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

# Writes `file:line:in 'label'` for one backtrace frame.
sig [Ptr, Ptr] => Void
machine def zr_buf_row(b, row)
  zr_buf_push(b, BtRow.file(row), BtRow.file_len(row))
  zr_buf_byte(b, 58)
  zr_buf_long(b, BtRow.line(row))
  zr_buf_push(b, Machine.bytes(":in '"), 5)
  zr_buf_label(b, BtRow.meta(row))
  zr_buf_byte(b, 39)
end

# `Exception#backtrace`: the value from set_backtrace, else the frames
# that the raise captured, or nil before the raise.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_exc_backtrace(recv, argc, argv, cref, blk)
  if RException.bt(recv) != QNIL
    return RException.bt(recv)
  end
  zr_exc_raise_rows(recv)
end

# Returns the frames that the raise captured, one `file:line:in 'label'`
# String each, or nil before a raise. set_backtrace does not change
# them, so `backtrace_locations` returns them.
sig [Value] => Value
machine def zr_exc_raise_rows(recv)
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

# Returns the prism node id of each frame that the raise captured, in
# the order of `zr_exc_raise_rows`, or nil before a raise.
sig [Value] => Value
machine def zr_exc_raise_nodes(recv)
  rows = RException.rows(recv)
  if rows == 0
    return Machine.value(QNIL)
  end
  n = RException.nrows(recv)
  out = zr_ary_new(n)
  i = 0
  while i < n
    zr_ary_push(out, zr_fix(BtRow.node(rows + (i * BtRow.size))))
    i += 1
  end
  out
end

# Returns the prism node id of each frame that `caller(start, limit)`
# would return for the caller, which is the Ruby method that calls this
# primitive.
sig [Value, Value] => Value
machine def zr_caller_nodes(start, limit)
  skip = zr_fix2long(start)
  room = limit == QNIL ? 0 - 1 : zr_fix2long(limit)
  out = zr_ary_new(8)
  rec = Task.top(zr_task())
  while rec != 0 && (room < 0 || RArray.len(out) < room)
    if zr_frame_shown_p(rec)
      if skip > 0
        skip -= 1
      else
        source = zr_frame_with_file(rec)
        zr_ary_push(out, zr_fix(source == 0 ? 0 : zr_frame_node_id(source)))
      end
    end
    rec = Frame.prev(rec)
  end
  out
end

# The class of an error that no rescue can catch by name: a deadlock.
G_FATAL = 41

sig [] => Value
machine def zr_fatal_class
  zr_global(G_FATAL)
end

sig [Value] => Value
machine def zr_error_print_m(exc)
  zr_error_print(exc)
  Machine.value(QNIL)
end

# Prints an uncaught exception on stderr, as CRuby does, then exits 1.
sig [Value] => Void
machine def zr_report(exc)
  zr_error_print(exc)
  exit(1)
end

# Prints an exception on stderr, then each exception in its cause list,
# as CRuby's rb_error_write does, and stops before `stop`. While the
# at_exit handlers run, `$!` is the exception that ends the program, so
# it becomes the cause of all that a handler raises. CRuby prints it
# once, at the end, not again under each handler. The kernel refuses a
# circular cause, so the loop always ends.
sig [Value, Value] => Void
machine def zr_error_print_upto(exc, stop)
  # Exception#uncaught_report writes as rb_error_write does. The frames
  # below are for a runtime that cannot run it yet.
  arg = Machine.slot(8)
  Machine.store64(arg, 0, Machine.word(stop == QUNDEF ? Machine.value(QNIL) : stop))
  text = zr_send(exc, Machine.id(:uncaught_report), 1, arg)
  if text != QUNDEF && !zr_special_p(text) && zr_type(text) == T_STRING
    zr_write_stderr(text)
    return
  end
  Task.set_pending(zr_task(), Machine.value(QNIL))
  e = exc
  while e != QNIL && e != QUNDEF && e != stop && !zr_special_p(e) && zr_is_a(e, zr_global(G_EXCEPTION))
    zr_error_print_one(e)
    e = RException.cause(e)
  end
end

# Prints the full cause list. All callers except an at_exit handler
# use this.
sig [Value] => Void
machine def zr_error_print(exc)
  zr_error_print_upto(exc, Machine.value(QUNDEF))
end

# Prints one exception on stderr, with its `detailed_message` after the
# first backtrace frame. A SystemStackError with more than 18 frames
# shows the first 9 and the last 4, and the count of the levels between.
sig [Value] => Void
machine def zr_error_print_one(exc)
  # `highlight:` is true when stderr is still the original terminal, as
  # rb_stderr_tty_p decides.
  opts = zr_hash_new()
  out = zr_gvar_get(Machine.id(:$stderr))
  original = zr_special_p(out) || out == zr_core_class(Machine.id(:STDERR))
  zr_hash_store(opts, zr_sym(Machine.id(:highlight)), zr_bool(original && Machine.word(isatty(Machine.i32(2))) != 0))
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(opts))
  zr_kw_pass()
  detail = zr_send(exc, Machine.id(:detailed_message), 1, slot)
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
  zr_write_stderr(zr_buf_take(b))
end

G_SYSTEM_STACK_ERROR = 35

# Raises for a Ruby frame that starts below the stack limit of the task.
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

# Sets a detail of an exception that the program reads. `NameError#name`
# and similar values are in ivars that the raise sets.
sig [Value, Word, Value] => Void
machine def zr_exc_detail(exc, id, v)
  zr_ivar_set(exc, id, v)
end

# `SystemCallError.new(message, errno)`: changes the class of the error
# to the Errno class for its errno, as syserr_initialize does.
sig [Value, Value] => Value
machine def zr_exc_set_class(exc, klass)
  RBasic.set_klass(exc, klass)
  exc
end

# Writes `file:line:in 'label'` for the live frame `rec`.
sig [Ptr, Ptr] => Void
machine def zr_buf_frame(b, rec)
  source = zr_frame_with_file(rec)
  if source != 0
    zr_buf_push(b, FrameMeta.file(Frame.meta(source)), FrameMeta.file_len(Frame.meta(source)))
    zr_buf_byte(b, 58)
    zr_buf_long(b, zr_frame_line(source))
  end
  zr_buf_push(b, Machine.bytes(":in '"), 5)
  zr_buf_label(b, zr_frame_label_meta(rec))
  zr_buf_byte(b, 39)
end

# Returns the meta that gives the backtrace label of the frame `rec`. A
# module function runs the code of one def from both of its methods, and
# that code has the module as its owner. A module is not an instance of
# itself, so a frame whose self is that module came through the
# singleton class. The frame then uses the meta of that method, which
# CRuby labels `Mod.name`.
sig [Ptr] => Ptr
machine def zr_frame_label_meta(rec)
  meta = Frame.meta(rec)
  owner = FrameMeta.owner(meta)
  if (FrameMeta.kind(meta) != KIND_DEF && FrameMeta.kind(meta) != KIND_BUILTIN) || Frame.self(rec) != owner || zr_type(owner) != T_MODULE
    return meta
  end
  single = RBasic.klass(owner)
  if !zr_singleton_p(single) || RClass.attached(single) != owner
    return meta
  end
  e = zr_find_method_at(single, FrameMeta.name(meta))
  if e == 0 || MEntry.meta(e) == 0 || FrameMeta.file(MEntry.meta(e)) != FrameMeta.file(meta) || FrameMeta.line(MEntry.meta(e)) != FrameMeta.line(meta)
    return meta
  end
  MEntry.meta(e)
end

# `Kernel#caller(start = 1, length = nil)`: the frames outward from the
# frame of the caller, after the first `start` frames.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_caller(recv, argc, argv, cref, blk)
  if argc > 2
    return zr_wrong_arity_range(argc, 0, 2)
  end
  if argc == 1 && zr_is_a(Machine.value(Machine.load64(argv, 0)), zr_global(G_RANGE))
    # `caller(range)`: the frames from this method's own outward, then the
    # range of them, as `caller(0)[range]` (ec_backtrace_to_ary).
    level = Machine.slot(8)
    Machine.store64(level, 0, Machine.word(zr_fix(0)))
    all = zr_kernel_caller(recv, 1, level, cref, blk)
    return all if all == QUNDEF
    return zr_send(all, Machine.id(:[]), 1, argv)
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
  while rec != 0
    if zr_frame_shown_p(rec)
      if start > 0
        start -= 1
      else
        if limit >= 0 && RArray.len(out) >= limit
          return out
        end
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

# Returns the frames of a suspended task, innermost first, each as
# `file:line:in 'label'`. `Thread#backtrace` reads another thread this
# way. A `limit` below zero means all frames. A `start` past the
# outermost frame returns nil, as `caller` does.
sig [Value, Value, Value] => Value
machine def zr_fiber_backtrace_m(fiber, start, limit)
  t = RFiber.task(fiber)
  if t == 0
    return Machine.value(QNIL)
  end
  skip = zr_fix2long(start)
  room = zr_fix2long(limit)
  out = zr_ary_new(8)
  rec = Task.top(t)
  while rec != 0
    if zr_frame_shown_p(rec)
      if skip > 0
        skip -= 1
      else
        if room >= 0 && RArray.len(out) >= room
          return out
        end
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_frame(b, rec)
        zr_ary_push(out, zr_buf_take(b))
      end
    end
    rec = Frame.prev(rec)
  end
  if skip > 0
    return Machine.value(QNIL)
  end
  out
end
