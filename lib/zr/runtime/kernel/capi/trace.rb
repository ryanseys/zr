module Zr::Kern
  # The C API of ruby/debug.h for tracers: a C TracePoint is the Ruby
  # TracePoint of core/trace_point.rb with a C function for its block, so
  # the events, the masks, the order of the hooks and the stop of nested
  # events are the same code for both. A hook's trace arg is its
  # TracePoint, and each rb_tracearg_* function sends the accessor of its
  # name, so C gets the answers that Ruby gets.

  # rb_tracepoint_new: a TracePoint that calls `func(tp, data)` for each
  # of `events`, in every thread: ruby's takes a thread too, but its hook
  # still hears every thread, as the name of that parameter
  # (`target_thread_not_supported_yet`) says.
  #: (value, i32, ptr, ptr) -> value
  def rb_tracepoint_new(_thread, events, func, data)
    Machine.gates_enter
    zr_c_entered()
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.sword(events) & 0xffffffff)))
    Machine.store64(argv, 8, Machine.word(zr_capi_hook(func, Machine.word(data), HOOK_POINT)))
    zr_c_result(zr_trace_point_send(zr_core_class(Machine.id(:TracePoint)), Machine.id(:c_point), 2, argv))
  end

  # The words of a C hook (zr_trace_call_c), as a String that its point
  # keeps.
  #: (ptr, word, word) -> value
  def zr_capi_hook(func, data, form)
    words = Machine.slot(24)
    Machine.store64(words, 0, Machine.word(func))
    Machine.store64(words, 8, data)
    Machine.store64(words, 16, form)
    zr_str_new(words, 24)
  end

  # rb_add_event_hook: `func(event, data, self, mid, klass)` for each of
  # `events` in every thread, until rb_remove_event_hook removes it. The
  # hook is a C TracePoint, on at once.
  #: (ptr, i32, value) -> void
  def rb_add_event_hook(func, events, data)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_add_hook(Machine.value(QNIL), func, events, data, Machine.i32(0))
  end

  # rb_add_event_hook2: the same, or with RUBY_EVENT_HOOK_FLAG_RAW_ARG
  # in `flags`, `func(data, arg)` with the trace arg.
  #: (ptr, i32, value, i32) -> void
  def rb_add_event_hook2(func, events, data, flags)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_add_hook(Machine.value(QNIL), func, events, data, flags)
  end

  # rb_thread_add_event_hook and rb_thread_add_event_hook2: a hook of the
  # events of `thread` alone.
  #: (value, ptr, i32, value) -> void
  def rb_thread_add_event_hook(thread, func, events, data)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_add_hook(thread, func, events, data, Machine.i32(0))
  end

  #: (value, ptr, i32, value, i32) -> void
  def rb_thread_add_event_hook2(thread, func, events, data, flags)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_add_hook(thread, func, events, data, flags)
  end

  # rb_remove_event_hook: removes each hook of every thread that calls
  # `func`; how many.
  #: (ptr) -> i32
  def rb_remove_event_hook(func)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_remove_hooks(Machine.value(QNIL), func, Machine.value(QUNDEF))
  end

  # rb_remove_event_hook_with_data: only the hooks whose data is `data`,
  # or every one for undef.
  #: (ptr, value) -> i32
  def rb_remove_event_hook_with_data(func, data)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_remove_hooks(Machine.value(QNIL), func, data)
  end

  #: (value, ptr) -> i32
  def rb_thread_remove_event_hook(thread, func)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_remove_hooks(thread, func, Machine.value(QUNDEF))
  end

  #: (value, ptr, value) -> i32
  def rb_thread_remove_event_hook_with_data(thread, func, data)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_remove_hooks(thread, func, data)
  end

  # RUBY_EVENT_HOOK_FLAG_RAW_ARG.
  EVENT_HOOK_RAW_ARG = 4

  # Adds the hook of `func` (TracePoint.c_hook) for `thread`, or every
  # thread for nil.
  #: (value, ptr, i32, value, i32) -> void
  def zr_capi_add_hook(thread, func, events, data, flags)
    form = (Machine.sword(flags) & EVENT_HOOK_RAW_ARG) != 0 ? HOOK_RAW : HOOK_EVENT
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.sword(events) & 0xffffffff)))
    Machine.store64(argv, 8, Machine.word(zr_capi_hook(func, Machine.word(data), form)))
    Machine.store64(argv, 16, Machine.word(thread))
    before = Machine.load64(Machine.static(:trace_events, 8), 0)
    zr_c_result(zr_trace_point_send(zr_core_class(Machine.id(:TracePoint)), Machine.id(:c_hook), 3, argv))
    zr_capi_trace_started(before)
  end

  # Removes the hooks of `thread` (nil: of every thread) that call `func`
  # with `data`, or with any data for undef (TracePoint.c_unhook); how
  # many.
  #: (value, ptr, value) -> i32
  def zr_capi_remove_hooks(thread, func, data)
    # Each String is a local until both are made: the slot is no root.
    words = Machine.slot(8)
    Machine.store64(words, 0, Machine.word(func))
    func_word = zr_str_new(words, 8)
    data_word = Machine.value(QNIL)
    if data != QUNDEF
      Machine.store64(words, 0, Machine.word(data))
      data_word = zr_str_new(words, 8)
    end
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(func_word))
    Machine.store64(argv, 8, Machine.word(data_word))
    Machine.store64(argv, 16, Machine.word(thread))
    removed = zr_c_result(zr_trace_point_send(zr_core_class(Machine.id(:TracePoint)), Machine.id(:c_unhook), 3, argv))
    Machine.i32(zr_fix2long(removed))
  end

  # rb_tracepoint_enable and rb_tracepoint_disable: turn the point on or
  # off. No call of TracePoint#enable runs, so no trace sees one. Both
  # give undef, as ruby's do.
  #: (value) -> value
  def rb_tracepoint_enable(tp)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_trace_switch(tp, Machine.value(QTRUE))
  end

  #: (value) -> value
  def rb_tracepoint_disable(tp)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_trace_switch(tp, Machine.value(QFALSE))
  end

  #: (value) -> value
  def rb_tracepoint_enabled_p(tp)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_trace_point_send(tp, Machine.id(:enabled?), 0, Machine.ptr(0)))
  end

  # rb_tracearg_from_tracepoint: the trace arg of the event that `tp`'s
  # hook handles, which is `tp` itself, or for an internal event the
  # kernel's record of it (internal_events.rb). Out of a hook it raises
  # RuntimeError, as ruby's does.
  #: (value) -> ptr
  def rb_tracearg_from_tracepoint(tp)
    Machine.gates_enter
    zr_c_entered()
    internal = zr_internal_arg()
    if InternalArg[internal].event != 0 && InternalArg[internal].point == tp
      return internal
    end
    zr_c_result(zr_trace_point_send(tp, Machine.id(:row), 0, Machine.ptr(0)))
    Machine.ptr(tp)
  end

  # rb_tracearg_event_flag: the event's RUBY_EVENT_* bit.
  #: (ptr) -> i32
  def rb_tracearg_event_flag(arg)
    Machine.gates_enter
    zr_c_entered()
    if arg == zr_internal_arg()
      return Machine.i32(InternalArg[arg].event)
    end
    Machine.i32(zr_fix2long(zr_capi_tracearg(arg, Machine.id(:event_flag))))
  end

  #: (ptr) -> value
  def rb_tracearg_event(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:event))
  end

  #: (ptr) -> value
  def rb_tracearg_path(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:path))
  end

  #: (ptr) -> value
  def rb_tracearg_lineno(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:lineno))
  end

  #: (ptr) -> value
  def rb_tracearg_method_id(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:method_id))
  end

  #: (ptr) -> value
  def rb_tracearg_callee_id(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:callee_id))
  end

  #: (ptr) -> value
  def rb_tracearg_defined_class(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:defined_class))
  end

  #: (ptr) -> value
  def rb_tracearg_binding(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:binding))
  end

  #: (ptr) -> value
  def rb_tracearg_self(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:self))
  end

  #: (ptr) -> value
  def rb_tracearg_return_value(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:return_value))
  end

  #: (ptr) -> value
  def rb_tracearg_raised_exception(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:raised_exception))
  end

  #: (ptr) -> value
  def rb_tracearg_parameters(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:parameters))
  end

  #: (ptr) -> value
  def rb_tracearg_eval_script(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:eval_script))
  end

  #: (ptr) -> value
  def rb_tracearg_instruction_sequence(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:instruction_sequence))
  end

  # rb_tracearg_object: the object that an internal event (NEWOBJ,
  # FREEOBJ) is about.
  #: (ptr) -> value
  def rb_tracearg_object(arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_tracearg(arg, Machine.id(:object))
  end

  # The accessor `mid` of the trace arg `arg`, a TracePoint.
  #: (ptr, word) -> value
  def zr_capi_tracearg(arg, mid)
    if arg == zr_internal_arg()
      return zr_capi_internal_tracearg(mid)
    end
    zr_c_result(zr_trace_point_send(Machine.value(arg), mid, 0, Machine.ptr(0)))
  end

  # The accessor `mid` of the trace arg of an internal event, which runs
  # no Ruby: the object, and the place, self and method of the frame that
  # runs. A FREEOBJ hook runs in the sweep, where no String can be made,
  # so it gets no path. Any other accessor gives nil.
  #: (word) -> value
  def zr_capi_internal_tracearg(mid)
    arg = zr_internal_arg()
    top = Task[zr_task()].top
    if mid == Machine.id(:object)
      return InternalArg[arg].object
    end
    if top == 0
      return Machine.value(QNIL)
    end
    if mid == Machine.id(:self)
      return Frame[top].self
    end
    rec = zr_frame_with_file(top)
    if mid == Machine.id(:lineno)
      return zr_fix(rec == 0 ? 0 : zr_frame_line(rec))
    end
    if mid == Machine.id(:path)
      return rec == 0 || InternalArg[arg].event != TRACE_NEWOBJ ? Machine.value(QNIL) : zr_meta_path(Frame[rec].meta)
    end
    method = zr_method_meta_of(top)
    if method == 0
      return Machine.value(QNIL)
    end
    if mid == Machine.id(:method_id) || mid == Machine.id(:callee_id)
      return zr_sym(FrameMeta[method].name)
    end
    if mid == Machine.id(:defined_class)
      return FrameMeta[method].owner
    end
    Machine.value(QNIL)
  end

  # Turns `tp` on or off.
  #: (value, value) -> value
  def zr_capi_trace_switch(tp, on)
    before = Machine.load64(Machine.static(:trace_events, 8), 0)
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(on))
    zr_c_result(zr_trace_point_send(tp, Machine.id(:c_switch), 1, argv))
    zr_capi_trace_started(before)
    Machine.value(QUNDEF)
  end

  # After C turned on a point or a hook, with `before` the mask of the
  # events that were on: when :c_return events start, the C method that
  # runs hears its own return, as ruby's hook sees the return of the C
  # function that runs (zr_capi_trace_returned).
  #: (word) -> void
  def zr_capi_trace_started(before)
    top = Task[zr_task()].top
    if (before & TRACE_C_RETURN) == 0 && (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_C_RETURN) != 0 &&
       zr_capi_method_frame_p(top)
      Machine.store64(Machine.static(:trace_c_returning, 8), 0, Machine.word(top))
    end
  end

  # Whether the frame `rec` runs a C method that an extension defined
  # (zr_capi_define), whose return zr_cfunc_call sees.
  #: (ptr) -> bool
  def zr_capi_method_frame_p(rec)
    if rec == 0 || Frame[rec].entry == 0
      return false
    end
    fn = FrameMeta[Frame[rec].meta].fn
    fn != 0 && MEntry[Frame[rec].entry].body == fn
  end

  # The result `value` of the C method whose frame is `rec`, after it
  # fires that method's :c_return when the method turned on the point
  # that hears it (zr_capi_trace_switch): its call began untraced.
  # Returns undef when a hook raised.
  #: (ptr, value, value) -> value
  def zr_capi_trace_returned(rec, recv, value)
    returning = Machine.static(:trace_c_returning, 8)
    if Machine.load64(returning, 0) != Machine.word(rec)
      return value
    end
    Machine.store64(returning, 0, 0)
    if value == QUNDEF
      return value
    end
    e = Frame[rec].entry
    r = zr_trace_c_send(TRACE_C_RETURN, e, zr_method_owner(zr_box_view(zr_class_of(recv)), MEntry[e].mid), recv, value)
    if r == QUNDEF
      return r
    end
    value
  end

  # Sends `mid` to a TracePoint, or to its class, as the core library
  # sends: its hidden methods answer, and no trace sees the call.
  #: (value, word, word, ptr) -> value
  def zr_trace_point_send(recv, mid, argc, argv)
    zr_dispatch(0, recv, mid, argc, argv, SEND_CORE, Machine.value(QNIL))
  end
end
