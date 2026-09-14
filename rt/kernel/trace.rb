# TracePoint's events. A program that names TracePoint is compiled with
# a test of `trace_events`, the events some enabled TracePoint asks for,
# at each point ruby fires one; a set bit brings the program here, and
# TracePoint.fire runs the handlers with a row that describes the frame
# the event is for.
TRACE_CALL = 8
TRACE_RETURN = 16
TRACE_RAISE = 128

# The events every enabled TracePoint asks for, together.
sig [Value] => Value
machine def zr_trace_events_set(mask)
  Machine.store64(Machine.static(:trace_events, 8), 0, zr_fix2long(mask))
  mask
end

# The traced frame fired `event`, leaving with `value`: undef while a
# raise unwinds it, which waits for the handlers. Answers `value`, or
# undef when a handler raised.
sig [Word, Value] => Value
machine def zr_trace_fire(event, value)
  t = zr_task()
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
# its owner, the frame's self, and the frame's serial, which finds the
# frame again for a binding.
sig [Ptr, Word, Value] => Value
machine def zr_trace_send(rec, event, value)
  row = zr_trace_row(event, value, Frame.meta(rec), Frame.line(rec))
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
  zr_send(zr_core_class(Machine.id(:TracePoint)), Machine.id(:fire), 1, argv)
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
  RProc.set_serial(b, Frame.line(rec))
  b
end
