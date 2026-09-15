# TracePoint's events. A program that names TracePoint is compiled with
# a test of `trace_events`, the events some enabled TracePoint asks for,
# at each point ruby fires one; a set bit brings the program here, and
# TracePoint.fire runs the handlers with a row that describes the frame
# the event is for.
TRACE_LINE = 1
TRACE_CALL = 8
TRACE_RETURN = 16
TRACE_C_CALL = 32
TRACE_C_RETURN = 64
TRACE_C = 96
TRACE_RAISE = 128

# The events every enabled TracePoint asks for, together. While a C
# event is on, no send site keeps its answer: every send reaches
# `zr_dispatch`, which fires the event around a method CRuby writes in C.
sig [Value] => Value
machine def zr_trace_events_set(mask)
  Machine.store64(Machine.static(:trace_points, 8), 0, zr_fix2long(mask))
  zr_trace_events_arm()
  mask
end

# `trace_events`, which compiled code tests: the TracePoints' events,
# and :line too while coverage is set up, which counts each line.
sig [] => Void
machine def zr_trace_events_arm
  events = Machine.static(:trace_events, 8)
  mask = Machine.load64(Machine.static(:trace_points, 8), 0)
  if zr_coverage_setup_p()
    mask = mask | TRACE_LINE
  end
  if ((Machine.load64(events, 0) ^ mask) & TRACE_C) != 0
    zr_methods_changed()
  end
  Machine.store64(events, 0, mask)
end

# Whether a C event is on.
sig [] => Bool
machine def zr_trace_c_p
  (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_C) != 0
end

# Whether entry `e` is a method CRuby writes in C: a builtin, an
# accessor, or a core def that CRuby does not write in Ruby. A frameless
# builtin, `send` or `Proc#call`, is one CRuby's VM calls without one.
sig [Ptr] => Bool
machine def zr_trace_c_entry_p(e)
  kind = MEntry.kind(e)
  if kind == KIND_ATTR_READER || kind == KIND_ATTR_WRITER
    return true
  end
  meta = MEntry.meta(e)
  if meta == 0 || (kind != KIND_DEF && kind != KIND_BUILTIN)
    return false
  end
  FrameMeta.kind(meta) == KIND_BUILTIN && FrameMeta.ruby(meta) == 0
end

# Whether the send on its way comes from Ruby: a program's frame, or a
# core def CRuby writes in Ruby. What the rest of the core library sends
# is a call in C, which fires nothing.
sig [] => Bool
machine def zr_trace_c_caller_p
  top = Task.top(zr_task())
  if top == 0
    return true
  end
  meta = Frame.meta(top)
  kind = FrameMeta.kind(meta)
  (kind != KIND_BUILTIN && kind != KIND_HIDDEN) || FrameMeta.ruby(meta) != 0
end

# The call through C method `e` between its `:c_call` and its
# `:c_return`, as vm_call_cfunc fires them: at the caller's file and
# line, and `:c_return` with nil when the call raises.
sig [Ptr, Value, Value, Word, Word, Ptr, Value, Word] => Value
machine def zr_trace_c_invoke(e, klass, recv, mid, argc, argv, blk, kw)
  owner = zr_method_owner(klass, mid)
  events = Machine.load64(Machine.static(:trace_events, 8), 0)
  if (events & TRACE_C_CALL) != 0
    r = zr_trace_c_send(TRACE_C_CALL, e, owner, recv, Machine.value(QNIL))
    return r if r == QUNDEF
  end
  value = zr_invoke(e, recv, argc, argv, blk, kw)
  if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_C_RETURN) == 0
    return value
  end
  t = zr_task()
  kind = Task.pending_kind(t)
  pending = Task.pending(t)
  r = zr_trace_c_send(TRACE_C_RETURN, e, owner, recv, value == QUNDEF ? Machine.value(QNIL) : value)
  return r if r == QUNDEF
  if value == QUNDEF
    Task.set_pending_kind(t, kind)
    Task.set_pending(t, pending)
  end
  value
end

sig [Word, Ptr, Value, Value, Value] => Value
machine def zr_trace_c_send(event, e, owner, recv, value)
  rec = zr_frame_with_file(Task.top(zr_task()))
  if rec == 0
    return Machine.value(QNIL)
  end
  row = zr_trace_row(event, value, Frame.meta(rec), zr_frame_line(rec))
  zr_ary_push(row, zr_sym(zr_method_original_id(e)))
  zr_ary_push(row, zr_sym(MEntry.mid(e)))
  zr_ary_push(row, owner)
  zr_ary_push(row, recv)
  zr_ary_push(row, Machine.value(QNIL))
  zr_ary_push(row, zr_fix(Machine.word(Frame.meta(rec))))
  zr_ary_push(row, zr_fix(e))
  zr_trace_run(row)
end

# The traced frame fired `event`, leaving with `value`: undef while a
# raise unwinds it, which waits for the handlers. Answers `value`, or
# undef when a handler raised.
sig [Word, Value] => Value
machine def zr_trace_fire(event, value)
  t = zr_task()
  if event == TRACE_LINE
    zr_coverage_line(Task.top(t))
    if (Machine.load64(Machine.static(:trace_points, 8), 0) & TRACE_LINE) == 0
      return value
    end
  end
  pending = Machine.value(QNIL)
  kind = Task.pending_kind(t)
  if value == QUNDEF
    pending = Task.pending(t)
    Task.set_pending(t, Machine.value(QNIL))
  end
  # A break or a return leaves with the value it carries; a raise with
  # none.
  shown = value
  if value == QUNDEF
    shown = kind == PENDING_RAISE || kind == PENDING_THROW ? Machine.value(QNIL) : pending
  end
  r = zr_trace_send(Task.top(t), event, shown)
  return r if r == QUNDEF
  if value == QUNDEF
    Task.set_pending_kind(t, kind)
    Task.set_pending(t, pending)
  end
  value
end

# A raise fires `:raise` from the program's frame: the one that raised,
# or the one that called the runtime's method that did. What the
# runtime raises for itself, deeper down, is no event of the program's.
sig [Value, Ptr] => Value
machine def zr_trace_raise(exc, top)
  if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_RAISE) == 0 || top == 0
    return Machine.value(QNIL)
  end
  rec = top
  if FrameMeta.kind(Frame.meta(rec)) == KIND_BUILTIN
    # A method CRuby writes in Ruby raises from its own file, which no
    # program shares.
    if FrameMeta.ruby(Frame.meta(rec)) != 0
      return Machine.value(QNIL)
    end
    rec = Frame.prev(rec)
  end
  if rec == 0 || FrameMeta.kind(Frame.meta(rec)) == KIND_BUILTIN || FrameMeta.kind(Frame.meta(rec)) == KIND_HIDDEN
    return Machine.value(QNIL)
  end
  zr_trace_send(rec, TRACE_RAISE, exc)
end

# TracePoint.fire with the row for frame `rec`: the event, the value,
# the path and line, the method's name and the name it was called by,
# its owner, the frame's self, the frame's serial, which finds the
# frame again for a binding, and the addresses of the code's FrameMeta
# and of the method entry, which answer its parameters.
sig [Ptr, Word, Value] => Value
machine def zr_trace_send(rec, event, value)
  row = zr_trace_row(event, value, Frame.meta(rec), zr_frame_line(rec))
  method = zr_method_meta_of(rec)
  entry = zr_bmethod_entry(rec)
  if method != 0 && FrameMeta.kind(method) == KIND_DEF
    zr_ary_push(row, zr_sym(FrameMeta.name(method)))
    home = rec
    while home != 0 && Frame.meta(home) != method
      home = Frame.prev(home)
    end
    zr_ary_push(row, zr_sym(home == 0 || Frame.mid(home) == 0 ? FrameMeta.name(method) : Frame.mid(home)))
    zr_ary_push(row, FrameMeta.owner(method))
  elsif entry != 0
    # A define_method body runs as a block, under its method's name.
    zr_ary_push(row, zr_sym(MEntry.mid(entry)))
    zr_ary_push(row, zr_sym(MEntry.mid(entry)))
    zr_ary_push(row, FrameMeta.owner(MEntry.meta(entry)))
  else
    zr_ary_push(row, Machine.value(QNIL))
    zr_ary_push(row, Machine.value(QNIL))
    zr_ary_push(row, Machine.value(QNIL))
  end
  zr_ary_push(row, Frame.self(rec))
  zr_ary_push(row, zr_fix(Frame.serial(rec)))
  zr_ary_push(row, zr_fix(Machine.word(Frame.meta(rec))))
  zr_ary_push(row, zr_fix(entry))
  zr_trace_run(row)
end

# The row's head: the event, the value, and where: the file of `meta`
# and `line`.
sig [Word, Value, Ptr, Word] => Value
machine def zr_trace_row(event, value, meta, line)
  row = zr_ary_new(9)
  zr_ary_push(row, zr_fix(event))
  zr_ary_push(row, value)
  zr_ary_push(row, zr_str_new(FrameMeta.file(meta), FrameMeta.file_len(meta)))
  zr_ary_push(row, zr_fix(line))
  row
end

sig [Value] => Value
machine def zr_trace_run(row)
  argv = Machine.slot(8)
  Machine.store64(argv, 0, Machine.word(row))
  zr_dispatch(0, zr_core_class(Machine.id(:TracePoint)), Machine.id(:fire), 1, argv, SEND_CORE, Machine.value(QNIL))
end

# A define_method method's `:call` or `:return`, fired around its body
# as vm_call_bmethod fires them, from the line its block starts on. A
# body the runtime wrote fires none.
sig [Word, Ptr, Value, Value] => Value
machine def zr_trace_bmethod(event, e, recv, value)
  meta = RProc.meta(MEntry.cref(e))
  if (Machine.load64(Machine.static(:trace_events, 8), 0) & event) == 0 || FrameMeta.file_len(meta) == 0
    return value
  end
  t = zr_task()
  pending = Machine.value(QNIL)
  kind = Task.pending_kind(t)
  if value == QUNDEF
    pending = Task.pending(t)
    Task.set_pending(t, Machine.value(QNIL))
  end
  row = zr_trace_row(event, value == QUNDEF ? Machine.value(QNIL) : value, meta, FrameMeta.line(meta))
  zr_ary_push(row, zr_sym(MEntry.mid(e)))
  zr_ary_push(row, zr_sym(MEntry.mid(e)))
  zr_ary_push(row, FrameMeta.owner(MEntry.meta(e)))
  zr_ary_push(row, recv)
  zr_ary_push(row, Machine.value(QNIL))
  zr_ary_push(row, zr_fix(Machine.word(meta)))
  zr_ary_push(row, zr_fix(e))
  r = zr_trace_run(row)
  return r if r == QUNDEF
  if value == QUNDEF
    Task.set_pending_kind(t, kind)
    Task.set_pending(t, pending)
  end
  value
end

# The binding of the live frame whose serial is `serial`, or nil once it
# has returned.
sig [Value] => Value
machine def zr_trace_binding(serial)
  rec = Task.top(zr_task())
  while rec != 0 && Frame.serial(rec) != zr_fix2long(serial)
    rec = Frame.prev(rec)
  end
  if rec == 0
    return Machine.value(QNIL)
  end
  b = zr_binding_of(Frame.meta(rec), zr_frame_env(rec), Frame.self(rec), Frame.cref(rec))
  RProc.set_blk(b, Frame.blk(rec))
  RProc.set_serial(b, zr_frame_line(rec))
  b
end

# TracePoint#parameters for a row: a C method's by its arity, a
# define_method body's as a method's, else those of the code the row's
# FrameMeta describes, a block's as a proc takes them.
sig [Value, Value] => Value
machine def zr_trace_parameters(meta_word, entry_word)
  e = Machine.ptr(zr_fix2long(entry_word))
  if e != 0 && MEntry.kind(e) == KIND_BMETHOD
    return zr_param_rows(FrameMeta.params(RProc.meta(MEntry.cref(e))), false)
  end
  if e != 0 && MEntry.kind(e) != KIND_DEF
    return zr_arity_rows(MEntry.arity(e))
  end
  meta = Machine.ptr(zr_fix2long(meta_word))
  if meta == 0 || FrameMeta.params(meta) == 0
    return zr_ary_new(0)
  end
  zr_param_rows(FrameMeta.params(meta), FrameMeta.kind(meta) == KIND_BLOCK)
end

# Whether the code `meta_word` describes is `target`'s or is written
# inside it, as a targeted TracePoint hooks an iseq and its children.
sig [Value, Value] => Value
machine def zr_trace_within(meta_word, target)
  goal = zr_iseq_meta(target)
  meta = Machine.ptr(zr_fix2long(meta_word))
  while meta != 0
    if meta == goal
      return Machine.value(QTRUE)
    end
    meta = FrameMeta.parent(meta)
  end
  Machine.value(QFALSE)
end
