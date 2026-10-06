module Zr::Kern
  # TracePoint events. When a program refers to TracePoint, the compiler
  # adds a check of `trace_events` at each point where ruby fires an
  # event. `trace_events` contains the events that the enabled
  # TracePoints need. A set bit sends the program here, and
  # TracePoint.fire runs the handlers with an event record (an Array)
  # that describes the frame of the event.
  TRACE_LINE = 1
  TRACE_CALL = 8
  TRACE_RETURN = 16
  TRACE_C_CALL = 32
  TRACE_C_RETURN = 64
  TRACE_C = 96
  # The events that a send fires around the method that it calls: a
  # method that CRuby writes in C, and a method that CRuby writes in Ruby.
  TRACE_SENDS = 120
  TRACE_RAISE = 128
  TRACE_RESCUE = 16384
  # Events that the machine fires, not a frame. The two thread events
  # fire from lib/zr/runtime/core/thread.rb, where the thread body starts and
  # ends. The fiber event fires here, at each of the four places where
  # control arrives after a switch.
  TRACE_FIBER_SWITCH = 4096
  # Fires when a string of Ruby, or a file that a require loads, is
  # compiled and is about to run.
  TRACE_SCRIPT_COMPILED = 8192
  # A block's :b_call and :b_return carry this bit when the block is a
  # lambda, which its parameters show (rb_tracearg_parameters).
  TRACE_LAMBDA = 1 << 32

  # Sets the union of the events of all enabled TracePoints. While a C
  # event is on, no send site uses its inline cache: each send goes to
  # `zr_dispatch`, which fires the event around a method that CRuby
  # writes in C.
  #: (value) -> value
  def zr_trace_events_set(mask)
    Machine.store64(Machine.static(:trace_points, 8), 0, zr_fix2long(mask))
    zr_trace_events_arm()
    mask
  end

  # Sets `trace_events`, which compiled code checks: the TracePoint
  # events, plus :line while coverage is set up, because coverage counts
  # each line.
  #: () -> void
  def zr_trace_events_arm
    events = Machine.static(:trace_events, 8)
    mask = Machine.load64(Machine.static(:trace_points, 8), 0)
    if zr_coverage_setup_p()
      mask = mask | TRACE_LINE
    end
    if ((Machine.load64(events, 0) ^ mask) & TRACE_SENDS) != 0
      zr_methods_changed()
    end
    Machine.store64(events, 0, mask)
  end

  # Whether a C event is on.
  #: () -> bool
  def zr_trace_c_p
    (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_C) != 0
  end

  # Whether an event that a send fires is on.
  #: () -> bool
  def zr_trace_sends_p
    (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_SENDS) != 0
  end

  # Marks a method that CRuby writes in Ruby. TracePoint sets this bit
  # (the second bit of MEntry.core) by name. A :call and a :return fire
  # around such a method, as around a method of the program.
  MENTRY_CRUBY_RUBY = 2

  # Whether the program's own code fires trace events: its build saw a
  # name of TracePoint, or was asked for them (`zr_program_start`).
  #: () -> value
  def zr_trace_built_m
    zr_bool(Machine.load64(Machine.static(:trace_built, 8), 0) != 0)
  end

  # Whether any TracePoint is enabled now, for an eval that compiles its
  # string with the events armed only while one can fire.
  #: () -> value
  def zr_trace_armed_m
    zr_bool(Machine.load64(Machine.static(:trace_events, 8), 0) != 0)
  end

  #: (ptr) -> bool
  def zr_trace_ruby_entry_p(e)
    (MEntry[e].core & MENTRY_CRUBY_RUBY) != 0
  end

  # Marks the method `name` of `klass` as a method that CRuby writes in
  # Ruby. Returns false if the class itself does not define that method.
  #: (value, value) -> value
  def zr_trace_mark_ruby(klass, name)
    e = zr_find_method_at(klass, zr_sym2id(name))
    if e == 0 || MEntry[e].kind == KIND_UNDEF
      return Machine.value(QFALSE)
    end
    MEntry[e].core = MEntry[e].core | MENTRY_CRUBY_RUBY
    Machine.value(QTRUE)
  end

  # Whether the method entry `e` is a method that CRuby writes in C: a
  # builtin, an accessor, or a core def that CRuby does not write in Ruby.
  # A builtin with no frame (`send` or `Proc#call`) is one that CRuby's VM
  # calls with no frame.
  #: (ptr) -> bool
  def zr_trace_c_entry_p(e)
    kind = MEntry[e].kind
    if zr_trace_ruby_entry_p(e)
      return false
    end
    if zr_word_entry_p(kind)
      return true
    end
    meta = MEntry[e].meta
    if meta == 0 || (kind != KIND_DEF && kind != KIND_BUILTIN)
      return false
    end
    FrameMeta[meta].kind == KIND_BUILTIN && FrameMeta[meta].ruby == 0
  end

  # Whether the current send comes from a frame of the program. A send
  # from the core library is a call in C, which fires nothing. A core def
  # that CRuby writes in Ruby sends much less than the same def here,
  # because CRuby uses primitives, so its sends also fire nothing.
  #: () -> bool
  def zr_trace_c_caller_p
    zr_trace_program_frame_p(Task[zr_task()].top)
  end

  # Whether the frame `rec` is the program's, not the core library's.
  #: (ptr) -> bool
  def zr_trace_program_frame_p(rec)
    if rec == 0
      return true
    end
    meta = Frame[rec].meta
    kind = FrameMeta[meta].kind
    kind != KIND_BUILTIN && kind != KIND_HIDDEN && FrameMeta[meta].hidden == 0
  end

  # Calls through the method entry `e` and fires an event before and
  # after it: `:c_call` and `:c_return` around a method that CRuby writes
  # in C, as vm_call_cfunc fires them, or `:call` and `:return` around a
  # method that CRuby writes in Ruby. Both fire at the file and line of
  # the caller, which TracePoint gives as the location of a Ruby method.
  # The event after the call has nil when the call raises.
  #: (ptr, value, word, word, ptr, value, word, word) -> value
  def zr_trace_send_invoke(e, recv, mid, argc, argv, blk, kw, before)
    zr_trace_owned_invoke(e, zr_method_owner(zr_box_view(zr_class_of(recv)), mid), recv, argc, argv, blk, kw, before)
  end

  # The same, for an entry of `owner`, which `super` finds above the
  # receiver's own method.
  #: (ptr, value, value, word, ptr, value, word, word) -> value
  def zr_trace_owned_invoke(e, owner, recv, argc, argv, blk, kw, before)
    after = before * 2
    events = Machine.load64(Machine.static(:trace_events, 8), 0)
    if (events & before) != 0
      r = zr_trace_c_send(before, e, owner, recv, Machine.value(QNIL))
      return r if r == QUNDEF
    end
    value = zr_invoke(e, recv, argc, argv, blk, kw)
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & after) == 0
      return value
    end
    t = zr_task()
    # A `raise` fired its :c_return before it raised (zr_trace_raise_jump).
    jumped = Machine.static(:raise_jumped, 16)
    if value == QUNDEF && Machine.load64(jumped, 0) == Machine.word(t) && Machine.load64(jumped, 8) == Machine.word(Task[t].top)
      Machine.store64(jumped, 0, 0)
      return value
    end
    kind = Task[t].pending_kind
    pending = Task[t].pending
    r = zr_trace_c_send(after, e, owner, recv, value == QUNDEF ? Machine.value(QNIL) : value)
    return r if r == QUNDEF
    if value == QUNDEF
      Task[t].pending_kind = kind
      Task[t].pending = pending
    end
    value
  end

  # The :c_call and the :c_return of a C method that pops its own frame
  # before it raises, as ruby's method_missing and const_missing do
  # (rb_vm_pop_cfunc_frame): both fire, then the raise. Returns undef
  # when a handler raises.
  #: (value, word) -> value
  def zr_trace_c_popped(recv, mid)
    if !zr_trace_c_p() || !zr_trace_c_caller_p()
      return Machine.value(QNIL)
    end
    e = zr_find_method(zr_class_of(recv), mid)
    if e == 0
      return Machine.value(QNIL)
    end
    owner = zr_method_owner(zr_box_view(zr_class_of(recv)), mid)
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_C_CALL) != 0
      r = zr_trace_c_send(TRACE_C_CALL, e, owner, recv, Machine.value(QNIL))
      return r if r == QUNDEF
    end
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_C_RETURN) != 0
      r = zr_trace_c_send(TRACE_C_RETURN, e, owner, recv, Machine.value(QNIL))
      return r if r == QUNDEF
    end
    Machine.value(QNIL)
  end

  #: (word, ptr, value, value, value) -> value
  def zr_trace_c_send(event, e, owner, recv, value)
    rec = zr_frame_with_file(Task[zr_task()].top)
    if rec == 0
      return Machine.value(QNIL)
    end
    row = zr_trace_row(event, value, Frame[rec].meta, zr_frame_line(rec))
    zr_ary_push(row, zr_sym(zr_method_original_id(e)))
    zr_ary_push(row, zr_sym(MEntry[e].mid))
    zr_ary_push(row, owner)
    zr_ary_push(row, recv)
    zr_ary_push(row, Machine.value(QNIL))
    zr_ary_push(row, zr_fix(Machine.word(Frame[rec].meta)))
    zr_ary_push(row, zr_fix(e))
    zr_trace_run(row)
  end

  # Fires `event` for the traced frame, which leaves with `value`. `value`
  # is undef while a pending unwind leaves the frame, and the unwind waits
  # until the handlers finish. Returns `value`, or undef when a handler
  # raises.
  #: (word, value) -> value
  def zr_trace_fire(event, value)
    t = zr_task()
    if event == TRACE_LINE
      zr_coverage_line(Task[t].top)
      if (Machine.load64(Machine.static(:trace_points, 8), 0) & TRACE_LINE) == 0
        return value
      end
    end
    pending = Machine.value(QNIL)
    kind = Task[t].pending_kind
    if value == QUNDEF
      pending = Task[t].pending
      Task[t].pending = Machine.value(QNIL)
    end
    # Only the block that breaks leaves with the break's value. The frames
    # that a break, a return, a raise or a throw leaves on the way have
    # none, as CRuby's hooks see nil there. The frame that a return
    # returns from leaves as usual, with its value.
    shown = value
    if value == QUNDEF
      shown = kind == PENDING_BREAK && Task[t].top == Task[t].pending_from ? pending : Machine.value(QNIL)
    end
    r = zr_trace_send(Task[t].top, event, shown)
    return r if r == QUNDEF
    if value == QUNDEF
      Task[t].pending_kind = kind
      Task[t].pending = pending
    end
    value
  end

  # A raise fires `:raise` from the program frame: the frame that raised,
  # or the frame that called the runtime method that raised. A raise
  # deeper in the runtime, for its own use, is not a program event.
  #: (value, ptr) -> value
  def zr_trace_raise(exc, top)
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_RAISE) == 0 || top == 0
      return Machine.value(QNIL)
    end
    # The core's frames have no file. The one that the program called
    # (`outer`) is the C method that raised, as CRuby's raise event names
    # it, with the program's file and line.
    rec = top
    outer = Machine.ptr(0)
    while rec != 0 && (Frame[rec].meta == 0 || FrameMeta[Frame[rec].meta].file_len == 0)
      # A method that CRuby writes in Ruby raises from its own file, which
      # is not a program file.
      if Frame[rec].meta != 0 && FrameMeta[Frame[rec].meta].ruby != 0
        return Machine.value(QNIL)
      end
      outer = rec
      rec = Frame[rec].prev
    end
    if rec == 0 || FrameMeta[Frame[rec].meta].kind == KIND_BUILTIN || FrameMeta[Frame[rec].meta].kind == KIND_HIDDEN || FrameMeta[Frame[rec].meta].hidden != 0
      return Machine.value(QNIL)
    end
    # Kernel#raise leaves its own frame before it raises (rb_raise_jump),
    # so its event is the caller's.
    e = outer == 0 ? Machine.ptr(0) : Frame[outer].entry
    if e == 0 || MEntry[e].fn == Machine.addr(:zr_kernel_raise)
      return zr_trace_send(rec, TRACE_RAISE, exc)
    end
    self_ = Frame[outer].self
    zr_trace_c_send(TRACE_RAISE, e, zr_method_owner(zr_box_view(zr_class_of(self_)), MEntry[e].mid), self_, exc)
  end

  # Fires `:rescue` when a rescue clause starts, from the frame of the
  # clause, with the exception that it caught. The event is at the line of
  # the matching clause, not at the raise (the `:raise` event gives that).
  # `line` is the line of the clause. The frame still has the line of the
  # raise, and a store to change it would slow each rescue, traced or not.
  #: (word) -> value
  def zr_trace_rescue(line)
    t = zr_task()
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_RESCUE) == 0
      return Machine.value(QNIL)
    end
    rec = Task[t].top
    if rec == 0 || FrameMeta[Frame[rec].meta].kind == KIND_BUILTIN || FrameMeta[Frame[rec].meta].kind == KIND_HIDDEN
      return Machine.value(QNIL)
    end
    zr_trace_send_at(rec, TRACE_RESCUE, Task[t].errinfo, line)
  end

  # Calls TracePoint.fire with the event record for frame `rec`. The
  # record contains the event, the value, the path and line, the method
  # name and the name used to call it, its owner, the self of the frame,
  # the frame serial (to find the frame again for a binding), and the
  # addresses of the FrameMeta and of the method entry (to get the
  # parameters).
  #: (ptr, word, value) -> value
  def zr_trace_send(rec, event, value)
    zr_trace_send_at(rec, event, value, zr_frame_line(rec))
  end

  # The same, for an event whose line is not the current line of the
  # frame: a rescue clause fires from its own line.
  #: (ptr, word, value, word) -> value
  def zr_trace_send_at(rec, event, value, line)
    row = zr_trace_row(event & (TRACE_LAMBDA - 1), value, Frame[rec].meta, line)
    method = zr_method_meta_of(rec)
    entry = zr_bmethod_entry(rec)
    if entry != 0 && zr_trace_in_bmethod_body(Frame[rec].meta, RProc[MEntry[entry].cref].meta)
      # A define_method body runs as a block, under its method's name:
      # the name it was defined with, and the name of the call. The def
      # that the block is written in is not the method.
      zr_ary_push(row, zr_sym(MEntry[entry].orig))
      zr_ary_push(row, zr_sym(MEntry[entry].mid))
      zr_ary_push(row, FrameMeta[MEntry[entry].meta].owner)
    elsif method != 0 && FrameMeta[method].kind == KIND_DEF
      zr_ary_push(row, zr_sym(FrameMeta[method].name))
      home = rec
      while home != 0 && Frame[home].meta != method
        home = Frame[home].prev
      end
      zr_ary_push(row, zr_sym(home == 0 || zr_frame_mid(home) == 0 ? FrameMeta[method].name : zr_frame_mid(home)))
      zr_ary_push(row, zr_trace_defined_class(home, method))
    else
      zr_ary_push(row, Machine.value(QNIL))
      zr_ary_push(row, Machine.value(QNIL))
      zr_ary_push(row, Machine.value(QNIL))
    end
    zr_ary_push(row, Frame[rec].self)
    zr_ary_push(row, zr_fix(zr_frame_serial(rec)))
    zr_ary_push(row, zr_fix(Machine.word(Frame[rec].meta)))
    zr_ary_push(row, zr_fix(entry))
    zr_ary_push(row, zr_bool((event & TRACE_LAMBDA) != 0))
    zr_trace_run(row)
  end

  # Whether code of `meta` is written in the define_method body `body`,
  # and in no def inside that body.
  #: (ptr, ptr) -> bool
  def zr_trace_in_bmethod_body(meta, body)
    m = meta
    while m != 0
      if m == body
        return true
      end
      if FrameMeta[m].kind == KIND_DEF
        return false
      end
      m = FrameMeta[m].parent
    end
    false
  end

  # The class of the method that frame `home` runs: where the call found
  # it, since one compiled def can be defined on several classes (an eval
  # of the same string that runs again). Else its def's owner, and for a
  # module function's copy the singleton class, as its backtrace label
  # names it.
  #: (ptr, ptr) -> value
  def zr_trace_defined_class(home, method)
    if home == 0
      return FrameMeta[method].owner
    end
    found = Frame[home].defined
    if !zr_special_p(found) && zr_type(found) == T_ICLASS
      found = RClass[found].attached
    end
    if !zr_special_p(found) && (zr_type(found) == T_CLASS || zr_type(found) == T_MODULE)
      return found
    end
    FrameMeta[zr_frame_label_meta(home)].owner
  end

  # Whether an event record's method entry (its address as a Fixnum, or
  # 0) is a method of the core library.
  #: (value) -> value
  def zr_trace_core_entry_m(entry)
    e = Machine.ptr(zr_fix2long(entry))
    zr_bool(e != 0 && MEntry[e].core != 0)
  end

  # Makes the start of an event record: the event, the value, the file of
  # `meta`, and `line`.
  #: (word, value, ptr, word) -> value
  def zr_trace_row(event, value, meta, line)
    row = zr_ary_new(9)
    zr_ary_push(row, zr_fix(event))
    zr_ary_push(row, value)
    zr_ary_push(row, zr_meta_file(meta))
    zr_ary_push(row, zr_fix(line))
    row
  end

  # Fires `:fiber_switch` where control arrives, as fiber_switch in cont.c
  # fires it in the fiber that gets control. `self` is the thread (as
  # th->self is there), not the fiber.
  #
  # EXEC_EVENT_HOOK passes 0 for the id and the class. Then
  # fill_id_and_klass takes them from the frame of the switch:
  # `Fiber#resume`, `Fiber.yield` or `Fiber#transfer`. `recv` is that
  # receiver and `mid` is its name. They are nil and 0 in a fiber that has
  # run no line yet, because such a fiber has no location.
  #: (value, word) -> value
  def zr_trace_fiber_switch(recv, mid)
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_FIBER_SWITCH) == 0
      return Machine.value(QNIL)
    end
    this = zr_send(zr_core_class(Machine.id(:Thread)), Machine.id(:current), 0, 0)
    return this if this == QUNDEF

    rec = zr_frame_with_file(Task[zr_task()].top)
    row = zr_ary_new(11)
    zr_ary_push(row, zr_fix(TRACE_FIBER_SWITCH))
    zr_ary_push(row, Machine.value(QNIL))
    if rec == 0 || mid == 0
      zr_ary_push(row, Machine.value(QNIL))
      zr_ary_push(row, zr_fix(0))
    else
      zr_ary_push(row, zr_meta_file(Frame[rec].meta))
      zr_ary_push(row, zr_fix(zr_frame_line(rec)))
    end
    zr_ary_push(row, mid == 0 ? Machine.value(QNIL) : zr_sym(mid))
    zr_ary_push(row, mid == 0 ? Machine.value(QNIL) : zr_sym(mid))
    zr_ary_push(row, mid == 0 ? Machine.value(QNIL) : zr_method_owner(zr_box_view(zr_class_of(recv)), mid))
    zr_ary_push(row, this)
    zr_ary_push(row, rec == 0 || mid == 0 ? Machine.value(QNIL) : zr_fix(zr_frame_serial(rec)))
    zr_ary_push(row, zr_fix(0))
    zr_ary_push(row, zr_fix(0))
    zr_trace_run(row)
  end

  # The same, where control comes back with `v`. `v` is undef when the
  # fiber left a pending unwind. The pending unwind waits while the
  # handlers run, as in zr_trace_fire, and is restored after them.
  #: (value, value, word) -> value
  def zr_trace_fiber_switched(v, recv, mid)
    events = Machine.load64(Machine.static(:trace_events, 8), 0)
    if (events & (TRACE_FIBER_SWITCH | TRACE_RAISE)) == 0
      return v
    end
    t = zr_task()
    kind = Task[t].pending_kind
    pending = Task[t].pending
    if v == QUNDEF
      Task[t].pending = Machine.value(QNIL)
    end
    if (events & TRACE_FIBER_SWITCH) != 0
      r = zr_trace_fiber_switch(recv, mid)
      return r if r == QUNDEF
    end
    # An exception that comes with the switch (Fiber#raise, or the end of
    # a fiber that raised) raises again in the fiber that gets control,
    # which fires :raise there.
    if v == QUNDEF && kind == PENDING_RAISE
      r = zr_trace_raise(pending, Task[t].top)
      return r if r == QUNDEF
    end
    if v == QUNDEF
      Task[t].pending_kind = kind
      Task[t].pending = pending
    end
    v
  end

  # Makes the value that `eval_script` and `instruction_sequence` read:
  # the source string of the code, or nil for a file, and the three values
  # that `rb_iseqw_new` would give for it: its path, its label, and its
  # first line.
  #: (value, value, ptr, word, value) -> value
  def zr_trace_compiled_value(script, path, label, label_len, line)
    v = zr_ary_new(4)
    zr_ary_push(v, script)
    zr_ary_push(v, path)
    zr_ary_push(v, zr_str_new(label, label_len))
    zr_ary_push(v, line)
    v
  end

  # Makes and fires the `:script_compiled` event record for both firing
  # points: `value` at the location of `rec`, with the method name `mid`,
  # the owner `owner`, and `this` as self.
  #: (ptr, value, value, word, value) -> value
  def zr_trace_compiled(rec, value, this, mid, owner)
    row = zr_ary_new(11)
    zr_ary_push(row, zr_fix(TRACE_SCRIPT_COMPILED))
    zr_ary_push(row, value)
    if rec == 0
      zr_ary_push(row, Machine.value(QNIL))
      zr_ary_push(row, zr_fix(0))
    else
      zr_ary_push(row, zr_meta_file(Frame[rec].meta))
      zr_ary_push(row, zr_fix(zr_frame_line(rec)))
    end
    zr_ary_push(row, mid == 0 ? Machine.value(QNIL) : zr_sym(mid))
    zr_ary_push(row, mid == 0 ? Machine.value(QNIL) : zr_sym(mid))
    zr_ary_push(row, owner)
    zr_ary_push(row, this)
    zr_ary_push(row, rec == 0 ? Machine.value(QNIL) : zr_fix(zr_frame_serial(rec)))
    zr_ary_push(row, zr_fix(0))
    zr_ary_push(row, zr_fix(0))
    zr_trace_run(row)
  end

  # Fires `:script_compiled` for a string that the program evaluates:
  # `script`, compiled with the name `path` from the line `line`.
  #
  # The event belongs to the eval form that the program called, at the
  # location of the call. In CRuby that form is a C frame, which has the
  # self, the name and the owner but no location, so `rb_tracearg_path`
  # goes out to the nearest Ruby frame for the location. Here the forms
  # (lib/zr/runtime/lib/zr/eval/forms.rb) are ordinary Ruby, so this frame gives
  # the self, name and owner, and the frame before it gives the location.
  # For example, `1.instance_eval("...")` gives 1, `:instance_eval` and
  # BasicObject, at the line of the call.
  #: (value, value, value) -> value
  def zr_trace_script_compiled(script, path, line)
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_SCRIPT_COMPILED) == 0
      return Machine.value(QNIL)
    end
    form = Task[zr_task()].top
    meta = zr_method_meta_of(form)
    zr_trace_compiled(zr_frame_with_file(Frame[form].prev),
                      zr_trace_compiled_value(script, path, Machine.bytes("<compiled>"), 10, line),
                      Frame[form].self, zr_frame_mid(form),
                      meta == 0 ? Machine.value(QNIL) : FrameMeta[meta].owner)
  end

  # Fires `:script_compiled` for a file that a require (kind 0), a
  # require_relative (1) or a load (2) is about to run. ruby fires it when
  # the file compiles. Here the file compiles before the program starts,
  # so it fires at the first run of the file, which is the only moment
  # that the program can see.
  #
  # `require` has no frame of its own. A require that the compiler sees is
  # inline in the frame that contains it. A computed require comes here
  # through hidden frames, which `zr_frame_with_file` skips. In both cases
  # the result is the requiring frame, which ruby reports, with its self.
  #: (value, word) -> value
  def zr_trace_required(path, kind)
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_SCRIPT_COMPILED) == 0
      return Machine.value(QNIL)
    end
    rec = zr_frame_with_file(Task[zr_task()].top)
    mid = kind == 1 ? Machine.id(:require_relative) : (kind == 2 ? Machine.id(:load) : Machine.id(:require))
    zr_trace_compiled(rec,
                      zr_trace_compiled_value(Machine.value(QNIL), path, Machine.bytes("<top (required)>"), 16, zr_fix(0)),
                      rec == 0 ? Machine.value(QNIL) : Frame[rec].self, mid, zr_global(G_KERNEL))
  end

  #: (value) -> value
  def zr_trace_run(row)
    argv = Machine.slot(8)
    Machine.store64(argv, 0, Machine.word(row))
    zr_dispatch(0, zr_core_class(Machine.id(:TracePoint)), Machine.id(:fire), 1, argv, SEND_CORE, Machine.value(QNIL))
  end

  # Fires `:call` or `:return` around the body of a define_method method,
  # as vm_call_bmethod does, from the first line of its block. A body that
  # the runtime wrote fires no event.
  #: (word, ptr, value, value) -> value
  def zr_trace_bmethod(event, e, recv, value)
    meta = RProc[MEntry[e].cref].meta
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & event) == 0 || FrameMeta[meta].file_len == 0
      return value
    end
    t = zr_task()
    pending = Machine.value(QNIL)
    kind = Task[t].pending_kind
    if value == QUNDEF
      pending = Task[t].pending
      Task[t].pending = Machine.value(QNIL)
    end
    row = zr_trace_row(event, value == QUNDEF ? Machine.value(QNIL) : value, meta, FrameMeta[meta].line)
    zr_ary_push(row, zr_sym(MEntry[e].orig))
    zr_ary_push(row, zr_sym(MEntry[e].mid))
    zr_ary_push(row, FrameMeta[MEntry[e].meta].owner)
    zr_ary_push(row, recv)
    zr_ary_push(row, Machine.value(QNIL))
    zr_ary_push(row, zr_fix(Machine.word(meta)))
    zr_ary_push(row, zr_fix(e))
    r = zr_trace_run(row)
    return r if r == QUNDEF
    if value == QUNDEF
      Task[t].pending_kind = kind
      Task[t].pending = pending
    end
    value
  end

  # Returns the binding of the live frame whose serial is `serial`, or nil
  # after the frame returns.
  #: (value) -> value
  def zr_trace_binding(serial)
    rec = Task[zr_task()].top
    while rec != 0 && Frame[rec].serial != zr_fix2long(serial)
      rec = Frame[rec].prev
    end
    if rec == 0
      return Machine.value(QNIL)
    end
    blk = zr_block_proc(Frame[rec].blk)
    b = zr_binding_of(Frame[rec].meta, zr_frame_env(rec), Frame[rec].self, Frame[rec].cref)
    RProc[b].blk = blk
    RProc[b].serial = zr_frame_line(rec)
    b
  end

  # TracePoint#parameters for an event record. A C method gets them from
  # its arity. A define_method body gets them as a method does. All other
  # code gets them from the FrameMeta of the record, and a block that is
  # no lambda gets them as a proc does.
  #: (value, value, value) -> value
  def zr_trace_parameters(meta_word, entry_word, lambda)
    e = Machine.ptr(zr_fix2long(entry_word))
    if e != 0 && MEntry[e].kind == KIND_BMETHOD
      return zr_param_rows(FrameMeta[RProc[MEntry[e].cref].meta].params, false)
    end
    if e != 0 && MEntry[e].kind != KIND_DEF
      return zr_arity_rows(MEntry[e].arity)
    end
    meta = Machine.ptr(zr_fix2long(meta_word))
    if meta == 0 || FrameMeta[meta].params == 0
      return zr_ary_new(0)
    end
    zr_param_rows(FrameMeta[meta].params, FrameMeta[meta].kind == KIND_BLOCK && lambda != QTRUE)
  end

  # Whether the code of `meta_word` is `target` or is inside it, as a
  # targeted TracePoint hooks an iseq and its children.
  #: (value, value) -> value
  def zr_trace_within(meta_word, target)
    goal = zr_iseq_meta(target)
    meta = Machine.ptr(zr_fix2long(meta_word))
    while meta != 0
      if meta == goal
        return Machine.value(QTRUE)
      end
      meta = FrameMeta[meta].parent
    end
    Machine.value(QFALSE)
  end
end
