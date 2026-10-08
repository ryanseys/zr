module Zr::Kern
  # The C API of ruby/debug.h for sampling profilers (stackprof, vernier,
  # datadog): the frames that run, and jobs that run at the next safe
  # point (postponed_jobs.rb).
  #
  # A frame of rb_profile_frames is the address of its FrameMeta with the
  # Fixnum tag: no object is made, as a signal handler can make none; it
  # names the same code each time, as a profiler's table keys it; and the
  # collector's mark of it does nothing. As ruby gives a method's entry
  # for a method's frame, also for a block in it, the frame of a block in
  # a method names the method. The rb_profile_frame_* functions answer in
  # Ruby (RubyVM.profile_frame).

  # rb_profile_frames: the frames of the thread that runs, from the
  # innermost, after `start` of them, at most `limit`, into `buff`, and
  # each one's line into `lines` (0 for a C method); how many. A profiler
  # calls it from a signal handler, so it only reads the frames.
  #: (i32, i32, ptr, ptr) -> i32
  def rb_profile_frames(start, limit, buff, lines)
    Machine.gates_enter
    Machine.i32(zr_profile_frames(Task[zr_task()].top, Machine.sword(start), Machine.sword(limit), buff, lines))
  end

  # rb_profile_thread_frames: the same, for the frames of `thread`.
  #: (value, i32, i32, ptr, ptr) -> i32
  def rb_profile_thread_frames(thread, start, limit, buff, lines)
    Machine.gates_enter
    zr_c_entered()
    fiber = zr_c_result(zr_trace_point_send(thread, Machine.id(:local_fiber), 0, Machine.ptr(0)))
    t = RFiber[fiber].task
    if t == 0
      return Machine.i32(0)
    end
    Machine.i32(zr_profile_frames(Task[t].top, Machine.sword(start), Machine.sword(limit), buff, lines))
  end

  #: (ptr, word, word, ptr, ptr) -> word
  def zr_profile_frames(rec, start, limit, buff, lines)
    i = 0
    while rec != 0 && i < limit
      if zr_frame_shown_p(rec)
        if start > 0
          start -= 1
        else
          meta = zr_frame_label_meta(rec)
          native = zr_meta_native_p(meta)
          if !native
            method = zr_method_meta_of(rec)
            if method != 0
              meta = method
            end
          end
          Machine.store64(buff + (i * 8), 0, Machine.word(meta) | 1)
          if lines != 0
            Machine.store32(lines + (i * 4), 0, Machine.i32(native ? 0 : zr_frame_line(rec)))
          end
          i += 1
        end
      end
      rec = Frame[rec].prev
    end
    i
  end

  #: (value) -> value
  def rb_profile_frame_path(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:path))
  end

  #: (value) -> value
  def rb_profile_frame_absolute_path(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:absolute_path))
  end

  #: (value) -> value
  def rb_profile_frame_label(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:label))
  end

  #: (value) -> value
  def rb_profile_frame_base_label(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:base_label))
  end

  #: (value) -> value
  def rb_profile_frame_full_label(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:full_label))
  end

  #: (value) -> value
  def rb_profile_frame_first_lineno(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:first_lineno))
  end

  #: (value) -> value
  def rb_profile_frame_classpath(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:classpath))
  end

  #: (value) -> value
  def rb_profile_frame_singleton_method_p(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:singleton_method_p))
  end

  #: (value) -> value
  def rb_profile_frame_method_name(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:method_name))
  end

  #: (value) -> value
  def rb_profile_frame_qualified_method_name(frame)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_profile_frame(frame, Machine.id(:qualified_method_name))
  end

  # The answer `what` about the frame `frame` of rb_profile_frames; nil
  # for a value that is no such frame.
  #: (value, word) -> value
  def zr_capi_profile_frame(frame, what)
    if !zr_fixnum_p(frame)
      return Machine.value(QNIL)
    end
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.word(frame) - 1)))
    Machine.store64(argv, 8, Machine.word(zr_sym(what)))
    zr_c_result(zr_trace_point_send(zr_core_class(Machine.id(:RubyVM)), Machine.id(:profile_frame), 2, argv))
  end

  # rb_postponed_job_preregister: the handle of the slot of `func`: its
  # own slot, which takes `data`, or else a free one;
  # POSTPONED_JOB_HANDLE_INVALID when every slot is taken.
  #: (i32, ptr, ptr) -> i32
  def rb_postponed_job_preregister(flags, func, data)
    Machine.gates_enter
    Machine.i32(zr_postponed_slot(func, data))
  end

  # rb_postponed_job_trigger: `h`'s job runs at the next safe point. A
  # signal handler may call it.
  #: (i32) -> void
  def rb_postponed_job_trigger(h)
    Machine.gates_enter
    slot = Machine.u32(h)
    if slot < POSTPONED_JOBS
      zr_postponed_trigger(slot)
    end
  end

  # rb_postponed_job_register and rb_postponed_job_register_one: the job
  # `func(data)` runs at the next safe point; 0 when no slot is free.
  #: (i32, ptr, ptr) -> i32
  def rb_postponed_job_register(flags, func, data)
    Machine.gates_enter
    zr_postponed_register(func, data)
  end

  #: (i32, ptr, ptr) -> i32
  def rb_postponed_job_register_one(flags, func, data)
    Machine.gates_enter
    zr_postponed_register(func, data)
  end

  #: (ptr, ptr) -> i32
  def zr_postponed_register(func, data)
    slot = zr_postponed_slot(func, data)
    if slot == 4294967295
      return Machine.i32(0)
    end
    zr_postponed_trigger(slot)
    Machine.i32(1)
  end

  # The slot of `func`, which now has `data`: the one that has `func`,
  # or the first free one; 0xffffffff when none is.
  #: (ptr, ptr) -> word
  def zr_postponed_slot(func, data)
    i = 0
    while i < POSTPONED_JOBS
      at = zr_postponed_funcs() + (i * 8)
      if Machine.load64(at, 0) == 0 || Machine.load64(at, 0) == Machine.word(func)
        Machine.store64(zr_postponed_data() + (i * 8), 0, Machine.word(data))
        Machine.store64(at, 0, Machine.word(func))
        return i
      end
      i += 1
    end
    4294967295
  end
end
