module Zr::Kern
  # The debug inspector of ruby/debug.h: a debugger's view of the frames
  # that run, as byebug, debug_inspector and bindex read them. The
  # context that C gets is an Array, `[locations, frames]`: the frames are
  # the rows of zr_debug_frames_from, from the innermost shown frame
  # outward, and the locations are theirs (Thread.frame_locations). The
  # bindings and selves stay valid after the inspector closes.

  # The fields of a frame's row (zr_debug_frames_from).
  DEBUG_ROW_SELF = 2
  DEBUG_ROW_BINDING = 3
  DEBUG_ROW_META = 4
  DEBUG_ROW_CLASS = 5

  # rb_debug_inspector_open: `func(dc, data)` with the context of the
  # frames that run now; the result of `func`. Frame 0 is the innermost
  # one: the C method that opens the inspector, or in a TracePoint's hook
  # the frame that fired the event.
  #: (ptr, ptr) -> value
  def rb_debug_inspector_open(func, data)
    Machine.gates_enter
    zr_c_entered()
    frames = zr_debug_frames_from(Task[zr_task()].top)
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(frames))
    locations = zr_c_result(zr_trace_point_send(zr_core_class(Machine.id(:Thread)), Machine.id(:frame_locations), 1, argv))
    dc = zr_ary_new(2)
    zr_ary_push(dc, locations)
    zr_ary_push(dc, frames)
    args = Machine.slot(64)
    Machine.store64(args, 0, Machine.word(dc))
    Machine.store64(args, 8, Machine.word(data))
    if !zr_call_c_returned(func, args, 2)
      zr_c_unwind()
    end
    Machine.value(Machine.load64(args, 0))
  end

  #: (value) -> value
  def rb_debug_inspector_backtrace_locations(dc)
    Machine.gates_enter
    zr_c_entered()
    zr_ary_at(dc, 0)
  end

  #: (value, word) -> value
  def rb_debug_inspector_frame_self_get(dc, index)
    Machine.gates_enter
    zr_c_entered()
    zr_ary_at(zr_capi_debug_frame(dc, index), DEBUG_ROW_SELF)
  end

  # The class of the method that the frame runs, a module's for its
  # method; nil at the top level.
  #: (value, word) -> value
  def rb_debug_inspector_frame_class_get(dc, index)
    Machine.gates_enter
    zr_c_entered()
    zr_ary_at(zr_capi_debug_frame(dc, index), DEBUG_ROW_CLASS)
  end

  # The binding of a Ruby frame, which sees its locals; nil for a C
  # frame.
  #: (value, word) -> value
  def rb_debug_inspector_frame_binding_get(dc, index)
    Machine.gates_enter
    zr_c_entered()
    zr_ary_at(zr_capi_debug_frame(dc, index), DEBUG_ROW_BINDING)
  end

  # The code of a Ruby frame as a RubyVM::InstructionSequence; nil for a
  # C frame.
  #: (value, word) -> value
  def rb_debug_inspector_frame_iseq_get(dc, index)
    Machine.gates_enter
    zr_c_entered()
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(zr_ary_at(zr_capi_debug_frame(dc, index), DEBUG_ROW_META)))
    zr_c_result(zr_trace_point_send(zr_core_class(Machine.id(:Thread)), Machine.id(:frame_iseq), 1, argv))
  end

  # The depth of the frame: the count of shown frames from it outward,
  # which rb_debug_inspector_current_depth gives for the frame that runs.
  #: (value, word) -> value
  def rb_debug_inspector_frame_depth(dc, index)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_debug_frame(dc, index)
    zr_fix(RArray[zr_ary_at(dc, 1)].len - index)
  end

  #: () -> value
  def rb_debug_inspector_current_depth
    Machine.gates_enter
    zr_c_entered()
    depth = 0
    rec = Task[zr_task()].top
    while rec != 0
      if zr_frame_shown_p(rec)
        depth += 1
      end
      rec = Frame[rec].prev
    end
    zr_fix(depth)
  end

  # The row of frame `index` of the context `dc`. An index out of the
  # frames raises ArgumentError, as ruby's does.
  #: (value, word) -> value
  def zr_capi_debug_frame(dc, index)
    frames = zr_ary_at(dc, 1)
    if index < 0 || index >= RArray[frames].len
      zr_c_raise(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no such frame"), 13)
    end
    zr_ary_at(frames, index)
  end
end
