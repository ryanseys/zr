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
  end

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
    Frame[rec].line & 4294967295
  end

  #: (ptr) -> word
  def zr_frame_node_id(rec)
    Frame[rec].line >> 32
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
          BtRow[row].node = zr_frame_node_id(source)
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
    if RException[exc].rows == 0 && RException[exc].bt == QNIL
      zr_backtrace_capture(exc, top)
    end
    if RException[exc].bt != QNIL && RException[exc].rows != 0
      zr_xfree(RException[exc].rows)
      RException[exc].rows = 0
      RException[exc].nrows = 0
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

  # The end of a raise: the $DEBUG report, the `:raise` event, then the
  # exception in the pending slot of the task.
  #: (value, ptr) -> value
  def zr_raise_as_is(exc, top)
    t = zr_task()
    debug = zr_gvar_get(Machine.id(:$DEBUG))
    if debug != QNIL && debug != QFALSE && !zr_is_a(exc, zr_core_class(Machine.id(:SystemExit)))
      # A backtrace set by hand, or none at all, does not tell where the
      # raise is.
      at = exc
      if RException[exc].rows == 0
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

  # `when *list`: whether `=== subject` is truthy for an element.
  #: (value, value) -> value
  def zr_case_any(subject, list)
    list = zr_splat_to_a(list)
    return list if list == QUNDEF
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(subject))
    i = 0
    while i < RArray[list].len
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
    else
      e = zr_make_exception(argc, argv)
      return e if e == QUNDEF
    end
    # The cause is checked once the exception is made, as rb_f_raise
    # reads the first argument first.
    if cause != QUNDEF && cause != QNIL && (zr_special_p(cause) || zr_type(cause) != T_EXCEPTION)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception object expected"), 25)
    end
    if cause != QUNDEF
      r = zr_exc_check_cause(e, cause)
      return r if r == QUNDEF
      RException[e].cause = cause == e ? Machine.value(QNIL) : cause
    end
    zr_raise_from(e, top)
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
    if !zr_special_p(first) && zr_type(first) == T_STRING && argc == 1
      return zr_exc_new(zr_global(G_RUNTIME_ERROR), first)
    end
    if zr_find_method(zr_class_of(first), Machine.id(:exception)) == 0
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("exception class/object expected"), 31)
    end
    e = zr_send(first, Machine.id(:exception), argc > 1 ? 1 : 0, argv + 8)
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
    elsif cause != QNIL && (zr_special_p(cause) || zr_type(cause) != T_EXCEPTION)
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

  #: (value, ptr, word) -> value
  def zr_raise_msg(klass, bytes, len)
    zr_raise(zr_exc_new(klass, zr_str_new(bytes, len)))
  end

  # Raises with the message in `b`, and takes ownership of `b`.
  #: (value, ptr) -> value
  def zr_raise_buf(klass, b)
    zr_raise(zr_exc_new(klass, zr_buf_take(b)))
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
      while FrameMeta[outer].kind == KIND_BLOCK
        levels += 1
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
  # anonymous owner.
  #: (ptr, value, word) -> void
  def zr_buf_method_label(b, owner, name)
    if zr_type(owner) == T_ICLASS
      owner = RClass[owner].attached
    end
    if zr_singleton_p(owner)
      attached = RClass[owner].attached
      t = zr_type(attached)
      if (t == T_CLASS || t == T_MODULE) && RClass[attached].name != QNIL
        zr_buf_str(b, RClass[attached].name)
        zr_buf_byte(b, 46)
      end
    elsif RClass[owner].name != QNIL
      zr_buf_str(b, RClass[owner].name)
      zr_buf_byte(b, 35)
    end
    zr_buf_sym(b, name)
  end

  # Writes `file:line:in 'label'` for one backtrace frame.
  #: (ptr, ptr) -> void
  def zr_buf_row(b, row)
    zr_buf_push(b, BtRow[row].file, BtRow[row].file_len)
    zr_buf_byte(b, 58)
    zr_buf_long(b, BtRow[row].line)
    zr_buf_push(b, Machine.bytes(":in '"), 5)
    zr_buf_label(b, BtRow[row].meta)
    zr_buf_byte(b, 39)
  end

  # `Exception#backtrace`: the value from set_backtrace, else the frames
  # that the raise captured, or nil before the raise.
  #: (value, word, ptr, value, value) -> value
  def zr_exc_backtrace(recv, argc, argv, cref, blk)
    if RException[recv].bt != QNIL
      return RException[recv].bt
    end
    zr_exc_raise_rows(recv)
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

  # Returns the prism node id of each frame that the raise captured, in
  # the order of `zr_exc_raise_rows`, or nil before a raise.
  #: (value) -> value
  def zr_exc_raise_nodes(recv)
    rows = RException[recv].rows
    if rows == 0
      return Machine.value(QNIL)
    end
    n = RException[recv].nrows
    out = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(out, zr_fix(BtRow[rows + (i * BtRow.size)].node))
      i += 1
    end
    out
  end

  # Returns the prism node id of each frame that `caller(start, limit)`
  # would return for the caller, which is the Ruby method that calls this
  # primitive.
  #: (value, value) -> value
  def zr_caller_nodes(start, limit)
    skip = zr_fix2long(start)
    room = limit == QNIL ? 0 - 1 : zr_fix2long(limit)
    out = zr_ary_new(8)
    rec = Task[zr_task()].top
    while rec != 0 && (room < 0 || RArray[out].len < room)
      if zr_frame_shown_p(rec)
        if skip > 0
          skip -= 1
        else
          source = zr_frame_with_file(rec)
          zr_ary_push(out, zr_fix(source == 0 ? 0 : zr_frame_node_id(source)))
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
    zr_raise_msg(zr_global(G_SYSTEM_STACK_ERROR), Machine.bytes("stack level too deep"), 20)
  end

  # `set_backtrace`: an Array of Strings, one String, or nil.
  #: (value, value) -> value
  def zr_exc_set_backtrace_value(exc, bt)
    if bt == QNIL
      RException[exc].bt = bt
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

  # Writes `file:line:in 'label'` for the live frame `rec`.
  #: (ptr, ptr) -> void
  def zr_buf_frame(b, rec)
    source = zr_frame_with_file(rec)
    if source != 0
      zr_buf_push(b, FrameMeta[Frame[source].meta].file, FrameMeta[Frame[source].meta].file_len)
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
  #: (ptr) -> ptr
  def zr_frame_label_meta(rec)
    meta = Frame[rec].meta
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
    end
    out = zr_ary_new(8)
    rec = Frame[Task[zr_task()].top].prev
    while rec != 0
      if zr_frame_shown_p(rec)
        if start > 0
          start -= 1
        else
          if limit >= 0 && RArray[out].len >= limit
            return out
          end
          b = Machine.slot(Buf.size)
          zr_buf_init(b)
          zr_buf_frame(b, rec)
          zr_ary_push(out, zr_frame_text(b, rec))
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
        if skip > 0
          skip -= 1
        else
          if room >= 0 && RArray[out].len >= room
            return out
          end
          b = Machine.slot(Buf.size)
          zr_buf_init(b)
          zr_buf_frame(b, rec)
          zr_ary_push(out, zr_frame_text(b, rec))
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
