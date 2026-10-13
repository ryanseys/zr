module Zr::Kern
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
  # `twin` is set on the block literal of a `define_method` call in a
  # program that does not trace: a second function of the same body with
  # the method signature, which a send calls directly (`zr_entry_fn`). It
  # makes the same frame as the block, with no Proc copy. Else it is 0.
  # `end_line` is the line where the scope's code ends, its `end` or its
  # `}`, or 0 for a file's or an eval's (rb_iseq_code_location).
  # `reads_backref` is 1 on a program's block that reads `$~`, `$_` or a
  # part of `$~`: a Proc made of it keeps the `$~` of its scope, so it
  # sees that `$~` after its method returned or on another stack.
  class FrameMeta < Layout
    attr_accessor :name #: word
    attr_accessor :owner #: value
    attr_accessor :file #: ptr
    attr_accessor :file_len #: word
    attr_accessor :kind #: word
    attr_accessor :line #: word
    attr_accessor :parent #: ptr
    attr_accessor :arity #: word
    attr_accessor :params #: ptr
    attr_accessor :fn #: ptr
    attr_accessor :locals #: ptr
    attr_accessor :env #: word
    attr_accessor :box #: value
    attr_accessor :ruby #: word
    attr_accessor :captures #: ptr
    attr_accessor :node #: word
    attr_accessor :hidden #: word
    attr_accessor :cover #: word
    attr_accessor :twin #: ptr
    attr_accessor :owns_backref #: word
    attr_accessor :frameless #: word
    attr_accessor :blocks #: word
    attr_accessor :rescues #: ptr
    attr_accessor :reads_backref #: word
    attr_accessor :end_line #: word
    # The activation entry in force where a def or block is written, plus
    # one, or 0 (zr_entry_activation).
    attr_accessor :using #: word
    # Where a def's, block's or lambda's code starts and ends, as
    # rb_iseq_code_location gives it (Proc#source_range): the first
    # line, and the byte columns of the start and of the end, whose line
    # is `end_line`. `span_line` is 0 for any other scope.
    attr_accessor :span_line #: word
    attr_accessor :column #: word
    attr_accessor :end_column #: word
    # For a scope that an eval compiled, 1 plus the number of its kept
    # spots (Zr::Eval#kept_script), or 1 when it keeps none: its code has
    # no absolute path. 0 for any other scope.
    attr_accessor :evaled #: word
  end

  # FrameMeta `blocks` of a program's method: whether it uses the block it
  # gets (a block parameter, `yield`, `super` or `...`), as CRuby's
  # use_block flag. A method that does not warns when it gets one, once
  # at each call site.
  BLOCKS_UNKNOWN = 0
  BLOCKS_UNUSED = 1
  BLOCKS_USED = 2

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
  # ran, negative in code that an eval compiled (zr_frame_place_id), or 0.
  class BtRow < Layout
    attr_accessor :meta #: ptr
    attr_accessor :file #: ptr
    attr_accessor :file_len #: word
    attr_accessor :line #: word
    attr_accessor :node #: word
  end
  # `bt` is a backtrace that the program set, or nil to use the captured
  # frames. `cause` is undef until the raise sets it.
  class RException < Layout
    attr_reader :basic #: RBasic
    attr_accessor :message #: value
    attr_accessor :rows #: ptr
    attr_accessor :nrows #: word
    attr_accessor :bt #: value
    attr_accessor :cause #: value
    # The Strings of the captured frames once `backtrace` made them,
    # so each call returns the same Array, which a dup shares.
    attr_accessor :strs #: value
  end

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
  #: (value) -> void
  def zr_mark_backtrace_rows(exc)
    rows = RException[exc].rows
    i = 0
    while i < RException[exc].nrows
      zr_mark(FrameMeta[BtRow[rows + (i * BtRow.size)].meta].owner)
      i += 1
    end
  end

  # The line word of a frame contains the line in its low half and the id
  # of the prism node that runs in its high half.
  #: (ptr) -> word
  def zr_frame_line(rec)
    # A signed 32-bit line: an eval may start at a negative one.
    line = Frame[rec].line & 4294967295
    line >= 2147483648 ? line - 4294967296 : line
  end

#: (ptr) -> word
def zr_frame_node_id(rec)
  Frame[rec].line >> 32
end

# The node id that a Location keeps for the frame `rec`: negative for
# code that an eval compiled, whose source CRuby reads again only when
# RubyVM.keep_script_lines kept it (Thread::Backtrace::Location#source_range).
# Then the bits from 32 up hold the number of its kept spots.
#: (ptr) -> word
def zr_frame_place_id(rec)
  id = zr_frame_node_id(rec)
  evaled = FrameMeta[Frame[rec].meta].evaled
  if evaled == 0
    return id
  end
  0 - (id | ((evaled - 1) << 32))
end

  # The levels that the frame `rec` takes in a caller list. CRuby runs
  # a rescue clause in a frame of its own, which shows the clause's line
  # and hides the scope under it. So a scope in rescue clauses takes one
  # level more for each (Lower#rescues_table): a list that starts there
  # shows the clause, and one that starts a level further shows the
  # scope at the line of the clause's `begin`.
  #: (ptr) -> word
  def zr_frame_levels(rec)
    table = FrameMeta[Frame[rec].meta].rescues
    if table == 0
      return 1
    end
    node = zr_frame_node_id(rec)
    n = Machine.load64(table, 0)
    levels = 1
    i = 0
    while i < n
      if (Machine.load64(table + 8 + (i * 8), 0) >> 32) == node
        levels += 1
      end
      i += 1
    end
    levels
  end

  # The line that the frame `rec` shows at its own level `level`: its
  # line at 0, then the `begin` line of each rescue clause it runs in,
  # innermost first.
  #: (ptr, word) -> word
  def zr_frame_level_line(rec, level)
    if level == 0
      return zr_frame_line(rec)
    end
    table = FrameMeta[Frame[rec].meta].rescues
    node = zr_frame_node_id(rec)
    n = Machine.load64(table, 0)
    seen = 0
    i = 0
    while i < n
      word = Machine.load64(table + 8 + (i * 8), 0)
      if (word >> 32) == node
        seen += 1
        if seen == level
          line = word & 4294967295
          return line >= 2147483648 ? line - 4294967296 : line
        end
      end
      i += 1
    end
    zr_frame_line(rec)
  end

  # The nearest frame at or outside `rec` that has a file of its own.
  #: (ptr) -> ptr
  def zr_frame_with_file(rec)
    while rec != 0 && (FrameMeta[Frame[rec].meta].kind == KIND_BUILTIN || FrameMeta[Frame[rec].meta].kind == KIND_HIDDEN)
      rec = Frame[rec].prev
    end
    rec
  end

  # Whether `rec` shows in a backtrace. A private helper of the core
  # library does not show. A builtin that a helper calls on a core value
  # or on itself also does not show, because CRuby's C does that work with
  # no frame. A builtin that a helper calls on another plain object shows,
  # as the frame that rb_funcall pushes for it does.
  #: (ptr) -> bool
  def zr_frame_shown_p(rec)
    kind = FrameMeta[Frame[rec].meta].kind
    if kind == KIND_HIDDEN || FrameMeta[Frame[rec].meta].frameless != 0
      return false
    end
    helper = Frame[rec].prev
    if kind != KIND_BUILTIN || helper == 0 || !zr_frame_helper_p(helper)
      return true
    end
    me = Frame[rec].self
    !zr_special_p(me) && zr_type(me) == T_OBJECT && me != Frame[helper].self
  end

  # Whether `rec` runs a helper: a hidden def, or a block written in one.
  # A block of the core library is also hidden, and its parent refers to
  # the def that contains it. A def has no parent.
  #: (ptr) -> bool
  def zr_frame_helper_p(rec)
    meta = Frame[rec].meta
    while FrameMeta[meta].kind == KIND_HIDDEN && FrameMeta[meta].parent != 0
      meta = FrameMeta[meta].parent
    end
    FrameMeta[meta].kind == KIND_HIDDEN
  end

  # Captures one backtrace frame for each visible frame from `top`
  # outward. The new buffer has space for the full frame list, so the
  # visibility check runs once, while the frames are filled, and not also
  # in a first counting pass.
  #: (value, ptr) -> void
  def zr_backtrace_capture(exc, top)
    n = 0
    rec = top
    while rec != 0
      n += 1
      rec = Frame[rec].prev
    end
    rows = zr_xmalloc(n * BtRow.size)
    i = 0
    rec = top
    while rec != 0
      if zr_frame_shown_p(rec)
        row = rows + (i * BtRow.size)
        BtRow[row].meta = zr_frame_label_meta(rec)
        source = zr_frame_with_file(rec)
        if source == 0
          BtRow[row].file = 0
          BtRow[row].file_len = 0
          BtRow[row].line = 0
          BtRow[row].node = 0
        else
          BtRow[row].file = FrameMeta[Frame[source].meta].file
          BtRow[row].file_len = FrameMeta[Frame[source].meta].file_len
          BtRow[row].line = zr_frame_line(source)
          BtRow[row].node = zr_frame_place_id(source)
        end
        i += 1
      end
      rec = Frame[rec].prev
    end
    RException[exc].rows = rows
    RException[exc].nrows = i
    zr_write_barrier_all(exc)
  end

  #: (value, value) -> value
  def zr_exc_new(klass, message)
    e = zr_alloc(T_EXCEPTION, klass, RException.size)
    RException[e].message = message
    RException[e].rows = 0
    RException[e].nrows = 0
    RException[e].bt = Machine.value(QNIL)
    RException[e].cause = Machine.value(QUNDEF)
    RException[e].strs = Machine.value(QNIL)
    e
  end

  # Raises `exc` from the frame `top`. It captures the backtrace if the
  # exception has none, puts the exception in the pending slot of the
  # task, and returns `undef` for the caller to pass on.
  #: (value, ptr) -> value
  def zr_raise_from(exc, top)
    if zr_frozen_p(exc)
      # setup_exception raises a copy of a frozen exception that has a
      # backtrace or a cause. One with neither goes as it is, with none.
      if RException[exc].rows == 0 && RException[exc].bt == QNIL && RException[exc].cause == QUNDEF
        return zr_raise_as_is(exc, top)
      end
      exc = zr_send(exc, Machine.id(:dup), 0, 0)
      return exc if exc == QUNDEF
    end
    if RException[exc].bt == QFALSE
      zr_xfree(RException[exc].rows)
      RException[exc].rows = 0
      RException[exc].nrows = 0
      RException[exc].bt = Machine.value(QNIL)
      RException[exc].strs = Machine.value(QNIL)
    end
    # rb_get_backtrace: a program's own `backtrace` says whether the
    # exception has one already; nil lets the raise capture it.
    custom = zr_exc_backtrace_custom(exc)
    if RException[exc].rows == 0 && RException[exc].bt == QNIL && (custom == QUNDEF || custom == QNIL)
      zr_backtrace_capture(exc, top)
    end
    if RException[exc].bt != QNIL && RException[exc].rows != 0
      zr_xfree(RException[exc].rows)
      RException[exc].rows = 0
      RException[exc].nrows = 0
      RException[exc].strs = Machine.value(QNIL)
    end
    t = zr_task()
    if RException[exc].cause == QUNDEF
      cause = Task[t].errinfo
      r = zr_exc_check_cause(exc, cause)
      return r if r == QUNDEF
      RException[exc].cause = cause == exc ? Machine.value(QNIL) : cause
    end
    zr_raise_as_is(exc, top)
  end

  # What a program's own Exception#backtrace returns for `exc`, or QUNDEF
  # when the core's method answers. setup_exception calls it under its
  # own tag, so an error in it is dropped. A raise inside that call does
  # not call it again (rb_ec_set_raised), or a `backtrace` that raises
  # would recurse until the stack ends.
  #: (value) -> value
  def zr_exc_backtrace_custom(exc)
    e = zr_find_method(zr_class_of(exc), Machine.id(:backtrace))
    if e == 0 || MEntry[e].core != 0
      return Machine.value(QUNDEF)
    end
    asking = Machine.static(:backtrace_asking, 8)
    t = zr_task()
    if Machine.load64(asking, 0) == Machine.word(t)
      return Machine.value(QUNDEF)
    end
    was = Machine.load64(asking, 0)
    Machine.store64(asking, 0, Machine.word(t))
    r = zr_send(exc, Machine.id(:backtrace), 0, 0)
    Machine.store64(asking, 0, was)
    if r == QUNDEF
      Task[t].pending_kind = PENDING_RAISE
      Task[t].pending = Machine.value(QNIL)
      return Machine.value(QNIL)
    end
    r
  end

  # The end of a raise: the $DEBUG report, the `:raise` event, then the
  # exception in the pending slot of the task.
  #: (value, ptr) -> value
  def zr_raise_as_is(exc, top)
    t = zr_task()
    debug = zr_gvar_get(Machine.id(:$DEBUG))
    if debug != QNIL && debug != QFALSE && !zr_is_a(exc, zr_core_class(Machine.id(:SystemExit)))
      # The report names where this raise is, as rb_source_location does,
      # not the exception's own backtrace: one raised again elsewhere, or
      # one sent from another thread, has one from before.
      at = zr_exc_new(zr_core_class(Machine.id(:Exception)), Machine.value(QNIL))
      zr_backtrace_capture(at, top)
      arg = Machine.slot(8)
      Machine.store64(arg, 0, Machine.word(at))
      r = zr_send(exc, Machine.id(:debug_report), 1, arg)
      return r if r == QUNDEF
    end
    fired = zr_trace_raise(exc, top)
    return fired if fired == QUNDEF
    Task[t].pending_kind = PENDING_RAISE
    Task[t].pending = exc
    Machine.value(QUNDEF)
  end

  #: (value) -> value
  def zr_raise(exc)
    zr_raise_from(exc, Task[zr_task()].top)
  end

  # For a landing block with a rescue clause. Returns the pending
  # exception when the pending unwind is a raise, else undef (a break or
  # a return passes through).
  #: () -> value
  def zr_rescuable
    t = zr_task()
    if Task[t].pending_kind == PENDING_RAISE
      return Task[t].pending
    end
    Machine.value(QUNDEF)
  end

  # Whether a rescue clause for `klass` catches `exc`.
  #: (value, value) -> value
  def zr_exc_match(exc, klass)
    if zr_special_p(klass) || (zr_type(klass) != T_CLASS && zr_type(klass) != T_MODULE)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("class or module required for rescue clause"), 42)
    end
    e = zr_find_method(zr_box_view(zr_class_of(klass)), Machine.id(:===))
    if e != 0 && (FrameMeta[MEntry[e].meta].owner != zr_global(G_MODULE) || zr_trace_c_p())
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
  #: (value, value) -> value
  def zr_exc_match_any(exc, list)
    list = zr_splat_to_a(list)
    return list if list == QUNDEF
    i = 0
    while i < RArray[list].len
      r = zr_exc_match(exc, zr_ary_at(list, i))
      return r if r == QUNDEF
      if r == QTRUE
        return r
      end
      i += 1
    end
    Machine.value(QFALSE)
  end

  # `when *list`: whether `=== subject` is truthy for an element. `mode`
  # is the send's (SEND_CORE in eval's compiler, which ruby writes in C).
  #: (value, value, word) -> value
  def zr_case_any(subject, list, mode)
    list = zr_splat_to_a(list)
    return list if list == QUNDEF
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(subject))
    i = 0
    while i < RArray[list].len
      r = zr_dispatch(0, zr_ary_at(list, i), Machine.id(:===), 1, slot, mode, Machine.value(QNIL))
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
  #: (value) -> value
  def zr_any_truthy(list)
    list = zr_splat_to_a(list)
    return list if list == QUNDEF
    i = 0
    while i < RArray[list].len
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
  #: () -> value
  def zr_rescue_enter
    t = zr_task()
    prev = Task[t].errinfo
    Task[t].errinfo = Task[t].pending
    Task[t].pending = Machine.value(QNIL)
    prev
  end

  # A rescue whose clauses all missed passes the raise on. A clause's
  # test runs code (its class can autoload a file that raises and
  # rescues), and that can clear the task's pending raise, so the raise
  # is set again from the value that the landing took.
  #: (value) -> void
  def zr_rescue_miss(exc)
    t = zr_task()
    Task[t].pending = exc
    Task[t].pending_kind = PENDING_RAISE
  end

  #: () -> value
  def zr_errinfo
    Task[zr_task()].errinfo
  end

  #: (value) -> void
  def zr_errinfo_set(v)
    Task[zr_task()].errinfo = v
  end

  # An ensure body runs with the pending unwind set aside. Returns the
  # pending value, for the caller to keep, and writes the kind, home and
  # site to the three words at `out`. During the body, a raise stays
  # visible as `$!`.
  #: (ptr) -> value
  def zr_signal_take(out)
    t = zr_task()
    v = Task[t].pending
    Machine.store64(out, 0, Task[t].pending_kind)
    Machine.store64(out, 8, Task[t].pending_home)
    Machine.store64(out, 16, Task[t].pending_site)
    if Task[t].pending_kind == PENDING_RAISE
      Task[t].errinfo = v
    end
    Task[t].pending = Machine.value(QNIL)
    Task[t].pending_kind = PENDING_RAISE
    v
  end

  #: (value, ptr) -> value
  def zr_signal_restore(v, out)
    zr_signal(Machine.load64(out, 0), v, Machine.ptr(Machine.load64(out, 8)), Machine.load64(out, 16))
  end

  # `Kernel#raise`. With no arguments, it raises `$!` again. A String
  # gives a RuntimeError. For all other values, it calls `exception` with
  # the message (a class does this through `new`). A third argument is
  # the backtrace. `cause:` sets the cause, else `$!` is the cause. The
  # frame of `raise` itself is not in the backtrace.
  #: (value, word, ptr, value, value) -> value
  def zr_kernel_raise(recv, argc, argv, cref, blk)
    top = Frame[Task[zr_task()].top].prev
    cause = Machine.value(QUNDEF)
    if zr_kw_take() != 0
      # `raise` uses `cause:` itself. It gives all other keywords to
      # `exception` as one Hash argument.
      opts = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
      cause = zr_hash_lookup(opts, zr_sym(Machine.id(:cause)))
      if cause != QUNDEF
        rest = zr_hash_new()
        zr_hash_update(rest, opts)
        zr_hash_delete_m(rest, zr_sym(Machine.id(:cause)))
        if RHash[rest].live == 0
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
      e = Task[zr_task()].errinfo
      if e == QNIL
        e = zr_exc_new(zr_global(G_RUNTIME_ERROR), zr_str_new(Machine.bytes(""), 0))
      end
    elsif zr_trace_program_frame_p(top)
      e = zr_make_exception(argc, argv)
      return e if e == QUNDEF
    else
      e = zr_make_core_exception(argc, argv)
      return e if e == QUNDEF
      r = zr_trace_core_raise(e)
      return r if r == QUNDEF
    end
    # The cause is checked once the exception is made, as rb_f_raise
    # reads the first argument first.
    if cause != QUNDEF && cause != QNIL && (zr_special_p(cause) || zr_type(cause) != T_EXCEPTION)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception object expected"), 25)
    end
    # exc_setup_cause: an explicit nil keeps a cause the exception has,
    # and stops `$!` from becoming the cause of one that has none.
    if cause == QNIL
      if RException[e].cause == QUNDEF
        RException[e].cause = Machine.value(QNIL)
      end
    elsif cause != QUNDEF
      r = zr_exc_check_cause(e, cause)
      return r if r == QUNDEF
      RException[e].cause = cause == e ? Machine.value(QNIL) : cause
    end
    r = zr_trace_raise_jump(e)
    return r if r == QUNDEF
    zr_raise_from(e, top)
  end

  # rb_raise_jump: a `raise` that the program called leaves its own frame
  # before it raises, so its :c_return fires before the :raise event, and
  # rb_get_backtrace fires :c_call and :c_return of `backtrace` between
  # them. The unwind then fires no second :c_return (zr_trace_send_invoke).
  #: (value) -> value
  def zr_trace_raise_jump(e)
    t = zr_task()
    rec = Task[t].top
    if !zr_trace_sends_p() || rec == 0 || !zr_trace_program_frame_p(Frame[rec].prev)
      return Machine.value(QNIL)
    end
    r = zr_trace_c_left(t, rec)
    return r if r == QUNDEF
    events = Machine.load64(Machine.static(:trace_events, 8), 0)
    bt = zr_find_method(zr_class_of(e), Machine.id(:backtrace))
    if bt != 0 && MEntry[bt].core != 0 && zr_trace_c_entry_p(bt)
      owner = zr_method_owner(zr_class_of(e), Machine.id(:backtrace))
      if (events & TRACE_C_CALL) != 0
        r = zr_trace_c_send(TRACE_C_CALL, bt, owner, e, Machine.value(QNIL))
        return r if r == QUNDEF
      end
      if (events & TRACE_C_RETURN) != 0
        r = zr_trace_c_send(TRACE_C_RETURN, bt, owner, e, Machine.value(QNIL))
        return r if r == QUNDEF
      end
    end
    Machine.value(QNIL)
  end

  # The C method of frame `rec` leaves its frame before it raises
  # (rb_raise_jump, rb_vm_pop_cfunc_frame): its :c_return fires now, and
  # the unwind fires no second one (zr_trace_owned_invoke).
  #: (ptr, ptr) -> value
  def zr_trace_c_left(t, rec)
    entry = Frame[rec].entry
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & TRACE_C_RETURN) != 0
      # The class that holds the entry: for a `super`, the one above the
      # receiver's own method.
      owner = zr_entry_holder(zr_box_view(zr_class_of(Frame[rec].self)), entry)
      r = zr_trace_c_send(TRACE_C_RETURN, entry, owner, Frame[rec].self, Machine.value(QNIL))
      return r if r == QUNDEF
    end
    Machine.store64(Machine.static(:raise_jumped, 16), 0, Machine.word(t))
    Machine.store64(Machine.static(:raise_jumped, 16), 8, Machine.word(Frame[rec].prev))
    Machine.value(QNIL)
  end

  # rb_make_exception: the exception of `raise`'s 1 to 3 arguments. A
  # String alone is a RuntimeError's message; any other first argument
  # makes it with `exception`, and a third is its backtrace.
  #: (word, ptr) -> value
  def zr_make_exception(argc, argv)
    if argc > 3
      return zr_wrong_arity_range(argc, 0, 3)
    end
    first = Machine.value(Machine.load64(argv, 0))
    # A String alone is the message of a new RuntimeError, which
    # rb_exc_new_str makes with `new`, so its `initialize` runs.
    if !zr_special_p(first) && zr_type(first) == T_STRING && argc == 1
      e = zr_class_new_object(zr_global(G_RUNTIME_ERROR))
      return e if e == QUNDEF
      r = zr_send_for_caller(e, Machine.id(:initialize), 1, argv, Machine.value(QNIL))
      return r if r == QUNDEF
      return e
    end
    if zr_find_method(zr_class_of(first), Machine.id(:exception)) == 0
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception class/object expected"), 31)
    end
    e = zr_send_for_caller(first, Machine.id(:exception), argc > 1 ? 1 : 0, argv + 8, Machine.value(QNIL))
    return e if e == QUNDEF
    if zr_special_p(e) || zr_type(e) != T_EXCEPTION
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception object expected"), 25)
    end
    if argc == 3
      r = zr_send(e, Machine.id(:assign_backtrace), 1, argv + 16)
      return r if r == QUNDEF
    end
    e
  end

  # rb_exception_setup, for Thread#raise and Fiber#raise: the exception
  # of `args`, with its cause resolved now, from `cause` when `given`, else
  # from this thread's `$!`. So the thread or fiber that raises it later
  # adds no cause of its own. With no arguments it is a new RuntimeError,
  # not `$!` again.
  #: (value, value, value) -> value
  def zr_exception_setup_m(args, cause, given)
    argc = RArray[args].len
    if argc == 0
      if given != QFALSE
        return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("only cause is given with no arguments"), 37)
      end
      e = zr_exc_new(zr_global(G_RUNTIME_ERROR), zr_str_new(Machine.bytes(""), 0))
    else
      e = zr_make_exception(argc, RArray[args].ptr)
      return e if e == QUNDEF
    end
    if given == QFALSE
      cause = Task[zr_task()].errinfo
    elsif cause == QNIL
      # exc_setup_cause: an explicit nil sets nothing, so an exception
      # raised again keeps the cause it has.
      if RException[e].cause == QUNDEF
        RException[e].cause = Machine.value(QNIL)
      end
      return e
    elsif zr_special_p(cause) || zr_type(cause) != T_EXCEPTION
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception object expected"), 25)
    elsif cause != QNIL
      r = zr_exc_check_cause(e, cause)
      return r if r == QUNDEF
    end
    RException[e].cause = cause == e ? Machine.value(QNIL) : cause
    e
  end

  # Raises `circular causes` when `e` is in the cause list of `cause`.
  # An exception that is its own cause gets no cause.
  #: (value, value) -> value
  def zr_exc_check_cause(e, cause)
    if cause == e
      return Machine.value(QNIL)
    end
    c = cause
    while c != QNIL && c != QUNDEF
      if c == e
        return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("circular causes"), 15)
      end
      c = RException[c].cause
    end
    Machine.value(QNIL)
  end

  # Raises with the `len` bytes at `bytes`. The message is binary while
  # it is ASCII, as rb_raise's format makes it, else UTF-8.
  #: (value, ptr, word) -> value
  def zr_raise_msg(klass, bytes, len)
    index = zr_bytes_ascii_only_p(bytes, len) ? ENC_BINARY : ENC_UTF8
    zr_raise_new(klass, zr_str_new_at(bytes, len, index))
  end

  # Raises with the message in `b`, and takes ownership of `b`. The
  # message's encoding is as zr_raise_msg's.
  #: (value, ptr) -> value
  def zr_raise_buf(klass, b)
    zr_raise_new(klass, zr_buf_take_at(b, ENC_BINARY))
  end

  # rb_raise: a new error of `klass` with `message`, raised as
  # rb_exc_raise raises it.
  #: (value, value) -> value
  def zr_raise_new(klass, message)
    e = zr_exc_new_str(klass, message)
    return e if e == QUNDEF
    zr_exc_raise(e)
  end

  # rb_exc_new_str: a new error of `klass`, made with `initialize` and
  # its message.
  #: (value, value) -> value
  def zr_exc_new_str(klass, message)
    e = zr_exc_new(klass, message)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(message))
    r = zr_exc_init(e, 1, slot)
    return r if r == QUNDEF
    e
  end

  # rb_class_new_instance's `initialize` of an error that a core method
  # makes. Exception's own runs here directly, unless a TracePoint hears
  # the call; any other goes through a send, so one that the program
  # wrote for a core class runs.
  #: (value, word, ptr) -> value
  def zr_exc_init(e, argc, argv)
    init = zr_find_method(zr_class_of(e), Machine.id(:initialize))
    if init != 0 && MEntry[init].fn == Machine.addr(:zr_exc_initialize) && !(zr_trace_c_p() && zr_trace_c_heard_p())
      return zr_exc_initialize(e, argc, argv, Machine.value(QNIL), Machine.value(QNIL))
    end
    zr_send_for_caller(e, Machine.id(:initialize), argc, argv, Machine.value(QNIL))
  end

  # rb_exc_raise of an error that a core method made: it fires the C
  # events of `exception` and `backtrace` first (zr_trace_core_raise).
  #: (value) -> value
  def zr_exc_raise(e)
    r = zr_trace_core_raise(e)
    return r if r == QUNDEF
    zr_raise(e)
  end

  # The error of a `raise` in a core method, made as the C function that
  # CRuby has in its place makes it. rb_raise news the class with the
  # message and does not send the class `exception`; an error made before
  # goes as it is; a String alone is a RuntimeError's message. Any other
  # form goes through rb_make_exception.
  #: (word, ptr) -> value
  def zr_make_core_exception(argc, argv)
    first = Machine.value(Machine.load64(argv, 0))
    if argc > 2 || zr_special_p(first)
      return zr_make_exception(argc, argv)
    end
    type = zr_type(first)
    if type == T_EXCEPTION && argc == 1
      return first
    end
    klass = first
    args = argv + 8
    if type == T_STRING && argc == 1
      klass = zr_global(G_RUNTIME_ERROR)
      args = argv
      argc = 2
    elsif type != T_CLASS || !zr_class_inherits(first, zr_global(G_EXCEPTION))
      return zr_make_exception(argc, argv)
    end
    e = zr_class_new_object(klass)
    return e if e == QUNDEF
    r = zr_exc_init(e, argc - 1, args)
    return r if r == QUNDEF
    e
  end

  # Returns a class of the core library, found by its constant name.
  #: (word) -> value
  def zr_core_class(id)
    e = zr_const_row_in(zr_global(G_OBJECT), id, false)
    if e == 0
      zr_bug(Machine.bytes("a core class is missing at boot\n"), 32)
    end
    CEntry[e].value
  end

  # `block in label`, or `block (N levels) in label` for a nested block.
  #: (ptr, ptr) -> void
  def zr_buf_label(b, meta)
    zr_buf_label_as(b, meta, true)
  end

  # Writes the label. When `qualified`, a method label includes the
  # owner, as in a backtrace. Otherwise it is the name only, as in an
  # instruction sequence.
  #: (ptr, ptr, bool) -> void
  def zr_buf_label_as(b, meta, qualified)
    if FrameMeta[meta].kind == KIND_BLOCK
      levels = 1
      outer = FrameMeta[meta].parent
      # An eval's code takes the label of the code that calls eval, so a
      # block in it counts the blocks around the eval too.
      while FrameMeta[outer].kind == KIND_BLOCK || FrameMeta[outer].kind == KIND_EVAL
        if FrameMeta[outer].kind == KIND_BLOCK
          levels += 1
        end
        outer = FrameMeta[outer].parent
      end
      zr_buf_push(b, Machine.bytes("block "), 6)
      if levels > 1
        zr_buf_byte(b, 40)
        zr_buf_long(b, levels)
        zr_buf_push(b, Machine.bytes(" levels) "), 9)
      end
      zr_buf_push(b, Machine.bytes("in "), 3)
      zr_buf_label_as(b, outer, qualified)
    elsif FrameMeta[meta].kind == KIND_MAIN
      zr_buf_push(b, Machine.bytes("<main>"), 6)
    elsif FrameMeta[meta].kind == KIND_TOP
      zr_buf_push(b, Machine.bytes("<top (required)>"), 16)
    elsif FrameMeta[meta].kind == KIND_EVAL
      zr_buf_label_as(b, FrameMeta[meta].parent, qualified)
    elsif FrameMeta[meta].kind == KIND_COMPILED
      zr_buf_push(b, Machine.bytes("<compiled>"), 10)
    elsif FrameMeta[meta].kind == KIND_SCLASS
      zr_buf_push(b, Machine.bytes("singleton class"), 15)
    elsif FrameMeta[meta].kind == KIND_CLASS || FrameMeta[meta].kind == KIND_MODULE
      zr_buf_push(b, FrameMeta[meta].kind == KIND_CLASS ? Machine.bytes("<class:") : Machine.bytes("<module:"), FrameMeta[meta].kind == KIND_CLASS ? 7 : 8)
      zr_buf_sym(b, FrameMeta[meta].name)
      zr_buf_byte(b, 62)
    elsif qualified
      zr_buf_method_label(b, FrameMeta[meta].owner, FrameMeta[meta].name)
    else
      zr_buf_sym(b, FrameMeta[meta].name)
    end
  end

  # Writes `Owner#name`, or `Owner.name` for a singleton method of a
  # class, or the name only for a singleton method of an object or for an
  # owner with no permanent name (rb_gen_method_name).
  #: (ptr, value, word) -> void
  def zr_buf_method_label(b, owner, name)
    if zr_type(owner) == T_ICLASS
      owner = RClass[owner].attached
    end
    if zr_singleton_p(owner)
      attached = RClass[owner].attached
      t = zr_type(attached)
      if (t == T_CLASS || t == T_MODULE) && RClass[attached].name != QNIL && (RBasic[attached].flags & FL_TEMP_NAME) == 0
        zr_buf_str(b, RClass[attached].name)
        zr_buf_byte(b, 46)
      end
    elsif RClass[owner].name != QNIL && (RBasic[owner].flags & FL_TEMP_NAME) == 0
      zr_buf_str(b, RClass[owner].name)
      zr_buf_byte(b, 35)
    end
    zr_buf_sym(b, name)
  end

  # Writes `file:line:in 'label'` for one backtrace frame; a frame at line
  # 0 has no line, as location_format writes it.
  #: (ptr, ptr) -> void
  def zr_buf_row(b, row)
    if BtRow[row].file == 0
      zr_buf_program_name(b)
    else
      zr_buf_push(b, BtRow[row].file, BtRow[row].file_len)
    end
    if BtRow[row].line != 0
      zr_buf_byte(b, 58)
      zr_buf_long(b, BtRow[row].line)
    end
    zr_buf_push(b, Machine.bytes(":in '"), 5)
    zr_buf_label(b, BtRow[row].meta)
    zr_buf_byte(b, 39)
  end

  # `Exception#backtrace`: the value from set_backtrace, else the frames
  # that the raise captured, or nil before the raise.
  #: (value, word, ptr, value, value) -> value
  def zr_exc_backtrace(recv, argc, argv, cref, blk)
    if RException[recv].bt == QFALSE
      return Machine.value(QNIL)
    end
    if RException[recv].bt != QNIL
      return RException[recv].bt
    end
    if RException[recv].strs != QNIL
      return RException[recv].strs
    end
    strs = zr_exc_raise_rows(recv)
    RException[recv].strs = strs
    zr_write_barrier(recv, strs)
    strs
  end

  # Returns the frames that the raise captured, one `file:line:in 'label'`
  # String each, or nil before a raise. set_backtrace does not change
  # them, so `backtrace_locations` returns them.
  #: (value) -> value
  def zr_exc_raise_rows(recv)
    rows = RException[recv].rows
    if rows == 0
      return Machine.value(QNIL)
    end
    n = RException[recv].nrows
    out = zr_ary_new(n)
    i = 0
    while i < n
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      row = rows + (i * BtRow.size)
      zr_buf_row(b, row)
      line = zr_buf_take(b)
      if zr_main_file_p(BtRow[row].file, BtRow[row].file_len)
        line = zr_path_str(line)
      end
      zr_ary_push(out, line)
      i += 1
    end
    out
  end

  # Returns the prism node id and the line of each frame that the raise
  # captured, two entries a frame, in the order of `zr_exc_raise_rows`,
  # or nil before a raise. The line is false for a frame with no file.
  #: (value) -> value
  def zr_exc_raise_places(recv)
    rows = RException[recv].rows
    if rows == 0
      return Machine.value(QNIL)
    end
    n = RException[recv].nrows
    out = zr_ary_new(n * 2)
    i = 0
    while i < n
      row = rows + (i * BtRow.size)
      zr_ary_push(out, zr_fix(BtRow[row].node))
      zr_ary_push(out, BtRow[row].file == 0 ? Machine.value(QFALSE) : zr_fix(BtRow[row].line))
      i += 1
    end
    out
  end

  # Returns the prism node id and the line of each frame that
  # `caller(start, limit)` would return for the caller, which is the Ruby
  # method that calls this primitive: two entries a frame. The line is
  # false for a frame with no file.
  #: (value, value) -> value
  def zr_caller_places(start, limit)
    zr_frame_places(Task[zr_task()].top, zr_fix2long(start), limit == QNIL ? 0 - 1 : zr_fix2long(limit))
  end

  # The same for the frames that `fiber`'s backtrace shows
  # (zr_fiber_backtrace_m), or nil when it runs on no stack.
  #: (value, value, value) -> value
  def zr_fiber_places_m(fiber, start, limit)
    t = RFiber[fiber].task
    if t == 0
      return Machine.value(QNIL)
    end
    zr_frame_places(Task[t].top, zr_fix2long(start), zr_fix2long(limit))
  end

  # The places of the shown frames from `rec` down, past the first
  # `skip` levels, at most `room` of them (no limit when negative).
  #: (ptr, word, word) -> value
  def zr_frame_places(top, skip, room)
    left = skip
    rec = top
    out = zr_ary_new(8)
    while rec != 0 && (room < 0 || RArray[out].len < room * 2)
      if zr_frame_shown_p(rec)
        levels = zr_frame_levels(rec)
        if left >= levels
          left -= levels
        else
          source = zr_frame_with_file(rec)
          zr_ary_push(out, zr_fix(source == 0 ? 0 : zr_frame_place_id(source)))
          zr_ary_push(out, source == 0 ? Machine.value(QFALSE) : zr_fix(zr_frame_level_line(source, left)))
          left = 0
        end
      end
      rec = Frame[rec].prev
    end
    out
  end

  # The class of an error that no rescue can catch by name: a deadlock.
  G_FATAL = 41

  #: () -> value
  def zr_fatal_class
    zr_global(G_FATAL)
  end

  #: (value) -> value
  def zr_error_print_m(exc)
    zr_error_print(exc)
    Machine.value(QNIL)
  end

  # Prints an uncaught exception on stderr, as CRuby does, then exits 1.
  #: (value) -> void
  def zr_report(exc)
    zr_error_print(exc)
    Libc.exit(1)
  end

  # Prints an exception on stderr, then each exception in its cause list,
  # as CRuby's rb_error_write does, and stops before `stop`. While the
  # at_exit handlers run, `$!` is the exception that ends the program, so
  # it becomes the cause of all that a handler raises. CRuby prints it
  # once, at the end, not again under each handler. The kernel refuses a
  # circular cause, so the loop always ends.
  #: (value, value) -> void
  def zr_error_print_upto(exc, stop)
    # Exception#uncaught_report writes as rb_error_write does. The frames
    # below are for a runtime that cannot run it yet.
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(stop == QUNDEF ? Machine.value(QNIL) : stop))
    text = zr_send(exc, Machine.id(:uncaught_report), 1, arg)
    if text != QUNDEF && !zr_special_p(text) && zr_type(text) == T_STRING
      zr_write_stderr(text)
      return
    end
    Task[zr_task()].pending = Machine.value(QNIL)
    e = exc
    while e != QNIL && e != QUNDEF && e != stop && !zr_special_p(e) && zr_is_a(e, zr_global(G_EXCEPTION))
      zr_error_print_one(e)
      e = RException[e].cause
    end
  end

  # Prints the full cause list. All callers except an at_exit handler
  # use this.
  #: (value) -> void
  def zr_error_print(exc)
    zr_error_print_upto(exc, Machine.value(QUNDEF))
  end

  # Prints one exception on stderr, with its `detailed_message` after the
  # first backtrace frame. A SystemStackError with more than 18 frames
  # shows the first 9 and the last 4, and the count of the levels between.
  #: (value) -> void
  def zr_error_print_one(exc)
    # `highlight:` is true when stderr is still the original terminal, as
    # rb_stderr_tty_p decides.
    opts = zr_hash_new()
    out = zr_gvar_get(Machine.id(:$stderr))
    original = zr_special_p(out) || out == zr_core_class(Machine.id(:STDERR))
    zr_hash_store(opts, zr_sym(Machine.id(:highlight)), zr_bool(original && Machine.u32(Libc.isatty(Machine.i32(2))) != 0))
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(opts))
    zr_kw_pass()
    detail = zr_send(exc, Machine.id(:detailed_message), 1, slot)
    if detail == QUNDEF || zr_special_p(detail) || zr_type(detail) != T_STRING
      detail = zr_class_name_of(exc)
      Task[zr_task()].pending = Machine.value(QNIL)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    rows = RException[exc].rows
    n = RException[exc].nrows
    if n == 0
      zr_buf_str(b, detail)
      zr_buf_byte(b, 10)
    end
    skip_at = 0 - 1
    skip = 0
    limit = zr_backtrace_limit()
    if limit >= 0 && n - 2 > limit
      skip_at = limit + 1
      skip = n - skip_at
    end
    if zr_class_of(exc) == zr_global(G_SYSTEM_STACK_ERROR) && n > 18
      skip_at = 9
      skip = n - 13
    end
    i = 0
    while i < n
      if i == skip_at
        zr_buf_push(b, Machine.bytes("\t ... "), 6)
        zr_buf_long(b, skip)
        zr_buf_push(b, Machine.bytes(" levels...\n"), 11)
        i += skip
        if i >= n
          break
        end
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

  # `--backtrace-limit`: the frames an error report shows under its first
  # one, or -1 for all. The word keeps the limit plus one, so 0 is unset.
  #: () -> word
  def zr_backtrace_limit
    Machine.load64(Machine.static(:backtrace_limit, 8), 0) - 1
  end

  #: () -> value
  def zr_backtrace_limit_m
    zr_int_from_word(zr_backtrace_limit())
  end

  # The limit is a long, as ruby's: LONG_MAX plus one wraps to the word
  # below zero, and the read takes the one back.
  #: (value) -> value
  def zr_backtrace_limit_set(n)
    v = 0
    if zr_fixnum_p(n)
      v = zr_fix2long(n)
    else
      out = Machine.slot(8)
      zr_big_to_long(n, out)
      v = Machine.load64(out, 0)
    end
    Machine.store64(Machine.static(:backtrace_limit, 8), 0, v + 1)
    n
  end

  # Raises for a Ruby frame that starts below the stack limit of the task.
  # rb_protect: calls the block, and any unwind out of it (a raise, a
  # throw, a break or a return through it) stops here, after the ensure
  # clauses on its way ran. Returns the block's value, or `failed` after an
  # unwind.
  #: (value, value) -> value
  def zr_protect(failed, blk)
    r = zr_yield(blk, 0, 0)
    if r == QUNDEF
      t = zr_task()
      Task[t].pending = Machine.value(QNIL)
      Task[t].throw_tag = Machine.value(QNIL)
      Task[t].pending_kind = PENDING_RAISE
      Task[t].pending_home = Machine.ptr(0)
      return failed
    end
    r
  end

  # rb_memerror: a NoMemoryError with no backtrace, as ruby raises the one
  # it made at start, so an uncaught one prints no line.
  #: () -> value
  def zr_no_memory
    e = zr_exc_new(zr_core_class(Machine.id(:NoMemoryError)), zr_str_new(Machine.bytes("failed to allocate memory"), 25))
    zr_raise_as_is(e, Task[zr_task()].top)
  end

  #: () -> value
  def zr_stack_overflow
    # No `initialize` runs: the stack has no room for it, and CRuby raises
    # an error it made at start.
    zr_raise(zr_exc_new(zr_global(G_SYSTEM_STACK_ERROR), zr_str_new(Machine.bytes("stack level too deep"), 20)))
  end

  # `set_backtrace`: an Array of Strings, one String, or nil.
  #: (value, value) -> value
  def zr_exc_set_backtrace_value(exc, bt)
    # nil after a raise makes `backtrace` nil while the captured frames
    # stay for `backtrace_locations`; false marks this. The next raise
    # captures new frames.
    if bt == QNIL
      RException[exc].bt = RException[exc].rows != 0 ? Machine.value(QFALSE) : bt
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
    while i < RArray[bt].len
      v = zr_ary_at(bt, i)
      if zr_special_p(v) || zr_type(v) != T_STRING
        return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("backtrace must be an Array of String or an Array of Thread::Backtrace::Location"), 79)
      end
      i += 1
    end
    RException[exc].bt = bt
    bt
  end

  #: (value, word, ptr, value, value) -> value
  def zr_exc_set_backtrace(recv, argc, argv, cref, blk)
    zr_exc_set_backtrace_value(recv, Machine.value(Machine.load64(argv, 0)))
  end

  # Whether a raise set the cause (to nil too), as CRuby's cause ivar is
  # defined. Marshal writes the cause only then.
  #: (value) -> value
  def zr_exc_cause_set_p(e)
    zr_bool(RException[e].cause != QUNDEF)
  end

  # Marshal.load's cause of an exception that it rebuilds.
  #: (value, value) -> value
  def zr_exc_cause_set(e, cause)
    RException[e].cause = cause
    cause
  end

  #: (value, word, ptr, value, value) -> value
  def zr_exc_cause(recv, argc, argv, cref, blk)
    c = RException[recv].cause
    if c == QUNDEF
      return Machine.value(QNIL)
    end
    c
  end

  # Sets a detail of an exception that the program reads. `NameError#name`
  # and similar values are in ivars that the raise sets.
  #: (value, word, value) -> void
  def zr_exc_detail(exc, id, v)
    zr_ivar_set(exc, id, v)
  end

  # `SystemCallError.new(message, errno)`: changes the class of the error
  # to the Errno class for its errno, as syserr_initialize does.
  #: (value, value) -> value
  def zr_exc_set_class(exc, klass)
    RBasic[exc].klass = klass
    exc
  end

  # The text that `b` holds for the frame `rec`, as a String: in the path
  # encoding when the frame's file is the main file.
  #: (ptr, ptr) -> value
  def zr_frame_text(b, rec)
    line = zr_buf_take(b)
    source = zr_frame_with_file(rec)
    if source != 0 && zr_main_file_p(FrameMeta[Frame[source].meta].file, FrameMeta[Frame[source].meta].file_len)
      return zr_path_str(line)
    end
    line
  end

  # Writes `file:line:in 'label'` for the live frame `rec`, at its own
  # level `level` (zr_frame_levels).
  #: (ptr, ptr, word) -> void
  def zr_buf_frame(b, rec, level)
    source = zr_frame_with_file(rec)
    if source != 0
      zr_buf_push(b, FrameMeta[Frame[source].meta].file, FrameMeta[Frame[source].meta].file_len)
      line = zr_frame_level_line(source, level)
      if line != 0
        zr_buf_byte(b, 58)
        zr_buf_long(b, line)
      end
    else
      zr_buf_program_name(b)
    end
    zr_buf_push(b, Machine.bytes(":in '"), 5)
    zr_buf_label(b, zr_frame_label_meta(rec))
    zr_buf_byte(b, 39)
  end

  # Writes the program's name: the file of a C frame with no Ruby frame
  # under it (the base of a fiber or of a thread), as location_to_str
  # writes vm->progname.
  #: (ptr) -> void
  def zr_buf_program_name(b)
    name = zr_program_name()
    if name != QNIL && name != 0
      zr_buf_str(b, name)
    end
  end

  # Returns the meta that gives the backtrace label of the frame `rec`. A
  # module function runs the code of one def from both of its methods, and
  # that code has the module as its owner. A module is not an instance of
  # itself, so a frame whose self is that module came through the
  # singleton class. The frame then uses the meta of that method, which
  # CRuby labels `Mod.name`.
  #: (ptr) -> ptr
  def zr_frame_label_meta(rec)
    meta = Frame[rec].meta
    # A method that an alias reached shows the alias's owner, or a core
    # alias its own name: the entry's label meta is a copy of the frame's
    # (zr_alias).
    e = Frame[rec].entry
    if e != 0 && (FrameMeta[meta].kind == KIND_DEF || FrameMeta[meta].kind == KIND_BUILTIN)
      own = MEntry[e].label
      if own != 0 && own != meta && FrameMeta[own].file == FrameMeta[meta].file && FrameMeta[own].line == FrameMeta[meta].line
        return own
      end
    end
    owner = FrameMeta[meta].owner
    if (FrameMeta[meta].kind != KIND_DEF && FrameMeta[meta].kind != KIND_BUILTIN) || Frame[rec].self != owner || zr_type(owner) != T_MODULE
      return meta
    end
    single = RBasic[owner].klass
    if !zr_singleton_p(single) || RClass[single].attached != owner
      return meta
    end
    e = zr_find_method_at(single, FrameMeta[meta].name)
    if e == 0 || MEntry[e].meta == 0 || FrameMeta[MEntry[e].meta].file != FrameMeta[meta].file || FrameMeta[MEntry[e].meta].line != FrameMeta[meta].line
      return meta
    end
    MEntry[e].meta
  end

  # `Kernel#caller(start = 1, length = nil)`: the frames outward from the
  # frame of the caller, after the first `start` frames.
  #: (value, word, ptr, value, value) -> value
  def zr_kernel_caller(recv, argc, argv, cref, blk)
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
      # ec_backtrace_to_ary: a count of 0 is an empty list, whatever the
      # level.
      if limit == 0
        return zr_ary_new(0)
      end
    end
    out = zr_ary_new(8)
    rec = Frame[Task[zr_task()].top].prev
    while rec != 0
      if zr_frame_shown_p(rec)
        levels = zr_frame_levels(rec)
        if start >= levels
          start -= levels
        else
          if limit >= 0 && RArray[out].len >= limit
            return out
          end
          b = Machine.slot(Buf.size)
          zr_buf_init(b)
          zr_buf_frame(b, rec, start)
          zr_ary_push(out, zr_frame_text(b, rec))
          start = 0
        end
      end
      rec = Frame[rec].prev
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
  #: (value, value, value) -> value
  def zr_fiber_backtrace_m(fiber, start, limit)
    t = RFiber[fiber].task
    if t == 0
      return Machine.value(QNIL)
    end
    skip = zr_fix2long(start)
    room = zr_fix2long(limit)
    out = zr_ary_new(8)
    rec = Task[t].top
    while rec != 0
      if zr_frame_shown_p(rec)
        levels = zr_frame_levels(rec)
        if skip >= levels
          skip -= levels
        else
          if room >= 0 && RArray[out].len >= room
            return out
          end
          b = Machine.slot(Buf.size)
          zr_buf_init(b)
          zr_buf_frame(b, rec, skip)
          zr_ary_push(out, zr_frame_text(b, rec))
          skip = 0
        end
      end
      rec = Frame[rec].prev
    end
    if skip > 0
      return Machine.value(QNIL)
    end
    out
  end
end
