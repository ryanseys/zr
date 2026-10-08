# Dispatch: a lookup in the receiver's ancestor list, then a call
# through the method entry's code pointer. A miss raises NoMethodError.

module Zr::Kern
  # Raises the error for a miss, with CRuby's message. A bare identifier
  # (`vcall`) raises NameError and shows main as `main`. A `super` with no
  # method above it has its own message. `private_call?` is true for a call
  # with no receiver or `self` (`implicit`), as for `super`.
  #: (value, word, bool, bool, bool, word, ptr) -> value
  def zr_no_method_from(recv, mid, vcall, from_super, implicit, argc, argv)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    if from_super
      zr_buf_push(b, Machine.bytes("super: no superclass method '"), 29)
    elsif vcall
      zr_buf_push(b, Machine.bytes("undefined local variable or method '"), 36)
    else
      zr_buf_push(b, Machine.bytes("undefined method '"), 18)
    end
    zr_buf_sym(b, mid)
    zr_buf_push(b, Machine.bytes("' for "), 6)
    r = zr_buf_receiver(b, recv)
    return r if r == QUNDEF
    e = zr_exc_new(zr_global(vcall ? G_NAME_ERROR : G_NO_METHOD_ERROR), zr_buf_take_at(b, ENC_USASCII))
    zr_exc_detail(e, Machine.id(:name), zr_sym(mid))
    zr_exc_detail(e, Machine.id(:receiver), recv)
    if !vcall
      zr_exc_detail(e, Machine.id(:args), zr_ary_of(argc, argv))
      if implicit || from_super
        zr_exc_detail(e, Machine.id(:private_call), Machine.value(QTRUE))
      end
    end
    # Keep the locals of the Ruby scope that contains the send and of the
    # scopes around a block, for NameError#local_variables. CRuby's
    # name_err_init_attr keeps the frame's ISEQ for the same purpose.
    source = zr_frame_with_file(Task[zr_task()].top)
    if source != 0
      zr_exc_detail(e, Machine.id(:local_variables), zr_reachable_local_names(Frame[source].meta))
    end
    traced = zr_trace_missing_raise(e)
    return traced if traced == QUNDEF
    zr_raise(e)
  end

  # Raises `wrong number of arguments (given 3, expected 1..2)`. `max` is
  # equal to `min` for an exact count, and -1 for no limit. For a def with
  # required keywords, the message gives them after the count.
  #: (word, word, word, ptr, word) -> value
  def zr_wrong_arity_kw(given, min, max, ids, nkw)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong number of arguments (given "), 33)
    zr_buf_long(b, given)
    zr_buf_push(b, Machine.bytes(", expected "), 11)
    zr_buf_long(b, min)
    if max < 0
      zr_buf_byte(b, 43)
    elsif max != min
      zr_buf_push(b, Machine.bytes(".."), 2)
      zr_buf_long(b, max)
    end
    if nkw > 0
      zr_buf_push(b, Machine.bytes("; required keyword"), 18)
      if nkw > 1
        zr_buf_byte(b, 115)
      end
      zr_buf_push(b, Machine.bytes(": "), 2)
      i = 0
      while i < nkw
        if i > 0
          zr_buf_push(b, Machine.bytes(", "), 2)
        end
        zr_buf_sym(b, Machine.load64(ids + (i * 8), 0))
        i += 1
      end
    end
    zr_buf_byte(b, 41)
    zr_raise_arity(b)
  end

  # Raises the ArgumentError in `b` for the arguments of a call, and takes
  # ownership of `b`. CRuby raises it as it sets up the callee's frame,
  # before the frame is on the stack, so its :raise is the caller's
  # (zr_trace_raise).
  #: (ptr) -> value
  def zr_raise_arity(b)
    t = zr_task()
    raised = Machine.static(:arity_raised, 16)
    Machine.store64(raised, 0, Machine.word(t))
    Machine.store64(raised, 8, Machine.word(Task[t].top))
    zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
  end

  #: (ptr, word) -> value
  def zr_raise_arity_msg(bytes, len)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, bytes, len)
    zr_raise_arity(b)
  end

  #: (word, word) -> value
  def zr_wrong_arity(given, expected)
    zr_wrong_arity_kw(given, expected, expected, 0, 0)
  end

  #: (word, word, word) -> value
  def zr_wrong_arity_range(given, min, max)
    zr_wrong_arity_kw(given, min, max, 0, 0)
  end

  #: (word, word) -> value
  def zr_wrong_arity_min(given, min)
    zr_wrong_arity_kw(given, min, 0 - 1, 0, 0)
  end

  # A call that passes keywords sets the task's keyword word immediately
  # before the send. The word is 1 for a flagged trailing Hash. Otherwise
  # it is the address (above 1) of a table: the count, then the ids. The
  # table's values are the call's last arguments. This is how `k: v` pairs
  # with plain Symbol keys go to the callee. A compiled def reads the word
  # in its prologue. A def that declares keywords reads the table's values
  # by position (`zr_kw_shape`). A def that declares none makes the values
  # one Hash argument (`zr_kw_undeclared`). A builtin, an accessor or a
  # `method_missing` gets a flagged Hash, made from the table
  # (`zr_kw_tab_in`).
  #: () -> void
  def zr_kw_pass
    Task[zr_task()].kw = 1
  end

  # Puts the table's values into one Hash, in place of the first value.
  # Returns the new argument count.
  #: (word, word, ptr) -> word
  def zr_kw_tab_in(tab, argc, argv)
    n = Machine.load64(tab, 0)
    if n == 0
      return argc
    end
    count = argc - n
    h = zr_hash_new()
    i = 0
    while i < n
      zr_hash_store(h, zr_sym(Machine.load64(tab + 8 + (i * 8), 0)), Machine.value(Machine.load64(argv + ((count + i) * 8), 0)))
      i += 1
    end
    Machine.store64(argv + (count * 8), 0, Machine.word(h))
    count + 1
  end

  # Returns the argument count of a send whose last argument is the
  # keywords Hash. An empty Hash, as from `**{}`, is not passed.
  #: (word, ptr) -> word
  def zr_kw_argc(argc, argv)
    h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    if RHash[h].live == 0
      return argc - 1
    end
    zr_kw_pass()
    argc
  end

  # The keyword word after zr_kw_tab_in: 1 for the Hash that it made, or
  # 0 for a table of no keywords, which makes none.
  #: (word) -> word
  def zr_kw_hashed(tab)
    if Machine.load64(tab, 0) == 0
      return 0
    end
    1
  end

  # `zr_kw_argc` for a yield. An empty Hash is not passed, but the
  # keyword word is a table of no keywords: a block that ruby does not
  # count as simple then takes a lone Array whole, as
  # setup_parameters_complex allows no autosplat after a `**h`, even an
  # empty one. Every reader of a table finds no keywords in it.
  #: (word, ptr) -> word
  def zr_kw_argc_yield(argc, argv)
    h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    if RHash[h].live == 0
      Task[zr_task()].kw = Machine.word(Machine.static(:kw_none, 8))
      return argc - 1
    end
    zr_kw_pass()
    argc
  end

  # `ruby2_keywords`: the marked methods, by their function address.
  #: () -> ptr
  def zr_ruby2_fns
    Machine.static(:ruby2_fns, IvTab.size)
  end

  #: (value, value) -> value
  def zr_ruby2_mark_m(klass, name)
    slot = Machine.slot(8)
    r = zr_name_id(name, slot)
    return r if r == QUNDEF
    e = zr_find_method(klass, Machine.load64(slot, 0))
    if e != 0 && MEntry[e].kind == KIND_BMETHOD
      # A define_method method runs its block, and the block's function
      # binds the rest argument, so the mark goes on the block's function.
      zr_ivtab_set(zr_ruby2_fns(), Machine.word(RProc[MEntry[e].cref].fn), Machine.value(QTRUE))
    elsif e != 0 && MEntry[e].fn != 0
      zr_ivtab_set(zr_ruby2_fns(), Machine.word(MEntry[e].fn), Machine.value(QTRUE))
    end
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_ruby2_mark_proc(pr)
    zr_ivtab_set(zr_ruby2_fns(), Machine.word(RProc[pr].fn), Machine.value(QTRUE))
    pr
  end

  # For a def or block that declares no keywords, called with the keyword
  # word `kw` set. A table's values become one Hash argument. A
  # `ruby2_keywords` rest (the function `fn`, 0 for no rest) flags the Hash
  # that it gets, so a later `*rest` passes it as keywords again. Returns
  # the new argument count.
  #: (word, word, ptr, ptr) -> word
  def zr_kw_undeclared(kw, argc, argv, fn)
    # A table of no keywords (an empty `**{}` given to a block) makes no
    # Hash, so the last argument is a positional one and takes no flag.
    hashed = kw == 1
    if kw > 1
      hashed = zr_kw_hashed(Machine.ptr(kw)) == 1
      argc = zr_kw_tab_in(kw, argc, argv)
    end
    if hashed && fn != 0 && argc > 0 && zr_ivtab_get(zr_ruby2_fns(), Machine.word(fn)) != QUNDEF
      h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
      RBasic[h].flags = RBasic[h].flags | FL_RUBY2
    end
    argc
  end

  # A splat whose last element is a flagged Hash passes that Hash as
  # keywords, in a new Hash without the flag.
  #: (word, ptr) -> word
  def zr_kw_ruby2_out(argc, argv)
    if !zr_kw_ruby2_tail(argc, argv)
      return argc
    end
    zr_kw_argc(argc, argv)
  end

  # The same for a yield, where an empty flagged Hash still counts as
  # keywords given, so a block that takes keywords spreads no lone Array
  # (zr_kw_argc_yield, Bug #19759).
  #: (word, ptr) -> word
  def zr_kw_ruby2_out_yield(argc, argv)
    if !zr_kw_ruby2_tail(argc, argv)
      return argc
    end
    zr_kw_argc_yield(argc, argv)
  end

  # Whether the last of `argc` arguments is a flagged Hash; if so, it is
  # replaced with a copy without the flag.
  #: (word, ptr) -> bool
  def zr_kw_ruby2_tail(argc, argv)
    if argc == 0
      return false
    end
    h = Machine.value(Machine.load64(argv + ((argc - 1) * 8), 0))
    if zr_special_p(h) || zr_type(h) != T_HASH || (RBasic[h].flags & FL_RUBY2) == 0
      return false
    end
    copy = zr_hash_new()
    zr_hash_update(copy, h)
    Machine.store64(argv + ((argc - 1) * 8), 0, Machine.word(copy))
    true
  end

  #: () -> word
  def zr_kw_take
    t = zr_task()
    kw = Task[t].kw
    Task[t].kw = 0
    kw
  end

  # Why a call went to `method_missing`. The base `method_missing` uses it
  # for the message. Either no method has the name (called with an
  # implicit receiver, as a bare identifier, or with an explicit
  # receiver), or the method is private or protected.
  MISS_IMPLICIT = 1
  MISS_VCALL = 2
  MISS_EXPLICIT = 3
  MISS_PRIVATE = 4
  MISS_PROTECTED = 5
  MISS_SUPER = 6

  # Sends a miss to the receiver's `method_missing`, with the name before
  # the arguments. The base `method_missing` raises as a plain miss does.
  #: (value, word, word, ptr, value, word, word) -> value
  def zr_method_missing(recv, mid, argc, argv, blk, kw, reason)
    if reason != MISS_PRIVATE && reason != MISS_PROTECTED && reason != MISS_SUPER
      e = zr_imported_refined_method(recv, mid)
      if e != 0
        return zr_invoke(e, recv, argc, argv, blk, kw)
      end
    end
    if kw > 1
      argc = zr_kw_tab_in(kw, argc, argv)
      kw = zr_kw_hashed(kw)
    end
    # A call of a method_missing that the class undefined: the arguments
    # name the missing method, as raise_method_missing reads them.
    # A private or protected method_missing that is called by name is
    # refused as any such method is, by its own name.
    if mid == Machine.id(:method_missing) && reason != MISS_PRIVATE && reason != MISS_PROTECTED
      Task[zr_task()].missing = reason
      return zr_obj_method_missing(recv, argc, argv, Machine.value(QNIL), blk)
    end
    # A refined method_missing does not answer a miss: ruby looks it up
    # without the refinements in use.
    e = zr_search_method(zr_box_view(zr_class_of(recv)), Machine.id(:method_missing))
    if e == 0 || MEntry[e].fn == Machine.addr(:zr_obj_method_missing)
      traced = zr_trace_c_popped(recv, Machine.id(:method_missing))
      return traced if traced == QUNDEF
      return zr_miss_error(recv, mid, reason, argc, argv)
    end
    args = zr_xmalloc((argc + 1) * 8)
    Machine.store64(args, 0, Machine.word(zr_sym(mid)))
    zr_memcpy(args + 8, argv, argc * 8)
    Task[zr_task()].missing = reason
    r = zr_invoke(e, recv, argc + 1, args, blk, kw)
    zr_xfree(args)
    r
  end

  # A method that Refinement#import_methods copied runs with its
  # refinement active, as the cref of CRuby's copy has it. Its body was
  # compiled outside the `refine`, so its sends do not name the
  # refinement. Thus while such a method runs (zr_imported_invoke), a send
  # from a method that runs as a refinement's method looks with that
  # refinement active first, and so does a send that misses. Returns the
  # entry, or 0.
  #: (value, word) -> ptr
  def zr_imported_refined_method(recv, mid)
    t = zr_task()
    top = Task[t].top
    if top == 0 || Task[t].refine != QNIL
      return 0
    end
    # The code that sends is in a def, or in a block in it. The nearest
    # frame of that def tells where its method was found: in the
    # refinement for the copy, elsewhere for the module's own method.
    scope = zr_backref_scope_meta(Frame[top].meta)
    if scope == 0 || FrameMeta[scope].kind != KIND_DEF
      return 0
    end
    rec = top
    while rec != 0 && (Frame[rec].meta == 0 || FrameMeta[Frame[rec].meta].kind != KIND_DEF || FrameMeta[Frame[rec].meta].locals != FrameMeta[scope].locals)
      rec = Frame[rec].prev
    end
    if rec == 0
      return 0
    end
    r = Frame[rec].defined
    if zr_special_p(r) || zr_type(r) != T_MODULE || ClassExt[RClass[r].ext].refined == QNIL
      return 0
    end
    list = zr_ary_new(1)
    zr_ary_push(list, r)
    Task[t].refine = list
    e = zr_refined_search(zr_box_view(zr_class_of(recv)), mid)
    Task[t].refine = Machine.value(QNIL)
    e
  end

  # Whether a method that Refinement#import_methods copied runs now.
  #: () -> bool
  def zr_imports_running_p
    Machine.load64(Machine.static(:imports_running, 8), 0) != 0
  end

  # Calls a method that Refinement#import_methods copied. Its body's
  # sends, which the module's own method shares, look up under the
  # refinement while it runs (zr_imported_refined_method). So a new method
  # stamp leaves each cache entry stale, and no entry is filled until it
  # returns (zr_call_cache_fill). No cache entry holds such a method, so
  # each call of it comes here.
  #: (ptr, value, word, ptr, value) -> value
  def zr_imported_invoke(e, recv, argc, argv, blk)
    running = Machine.static(:imports_running, 8)
    Machine.store64(running, 0, Machine.load64(running, 0) + 1)
    Machine.store64(Machine.static(:site_stamp, 8), 0, 0 - 1)
    zr_methods_changed()
    r = Method.call(MEntry[e].fn, recv, argc, argv, e, blk, zr_entry_found(e))
    Machine.store64(running, 0, Machine.load64(running, 0) - 1)
    if Machine.load64(running, 0) == 0
      zr_methods_changed()
    end
    r
  end

  #: (value, word, word, word, ptr) -> value
  def zr_miss_error(recv, mid, reason, argc, argv)
    if reason == MISS_PRIVATE
      return zr_hidden_method(recv, mid, VIS_PRIVATE, argc, argv)
    end
    if reason == MISS_PROTECTED
      return zr_hidden_method(recv, mid, VIS_PROTECTED, argc, argv)
    end
    if reason == MISS_SUPER
      return zr_no_method_from(recv, mid, false, true, false, argc, argv)
    end
    zr_no_method_from(recv, mid, reason == MISS_VCALL, false, reason == MISS_IMPLICIT, argc, argv)
  end

  # `BasicObject#method_missing`: raises the NoMethodError for a miss.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_method_missing(recv, argc, argv, cref, blk)
    if argc < 1
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no method name given"), 20)
    end
    m = Machine.value(Machine.load64(argv, 0))
    unless zr_symbol_p(m)
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("method name must be a Symbol but "), 33)
      shown = zr_buf_class_shown(b, m)
      if shown == QUNDEF
        zr_buf_free(b)
        return shown
      end
      zr_buf_push(b, Machine.bytes(" is given"), 9)
      return zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b)
    end
    # The reason stays, as ec->method_missing_reason does in CRuby: a
    # direct call of method_missing reports the last miss's kind.
    zr_miss_error(recv, zr_sym2id(m), Task[zr_task()].missing, argc - 1, argv + 8)
  end

  #: (value, word, bool, word, ptr) -> value
  def zr_no_method(recv, mid, vcall, argc, argv)
    zr_no_method_from(recv, mid, vcall, false, false, argc, argv)
  end

  # Raises `private method 'x' called for ...`, or the protected form.
  #: (value, word, word, word, ptr) -> value
  def zr_hidden_method(recv, mid, vis, argc, argv)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, vis == VIS_PRIVATE ? Machine.bytes("private method '") : Machine.bytes("protected method '"), vis == VIS_PRIVATE ? 16 : 18)
    zr_buf_sym(b, mid)
    zr_buf_push(b, Machine.bytes("' called for "), 13)
    r = zr_buf_receiver(b, recv)
    return r if r == QUNDEF
    e = zr_exc_new(zr_global(G_NO_METHOD_ERROR), zr_buf_take_at(b, ENC_USASCII))
    zr_exc_detail(e, Machine.id(:name), zr_sym(mid))
    zr_exc_detail(e, Machine.id(:receiver), recv)
    zr_exc_detail(e, Machine.id(:args), zr_ary_of(argc, argv))
    # `private_call?` is true when the call had no explicit receiver. A
    # call that finds a private or protected method always has one.
    zr_exc_detail(e, Machine.id(:private_call), Machine.value(QFALSE))
    traced = zr_trace_missing_raise(e)
    return traced if traced == QUNDEF
    zr_raise(e)
  end

  # Writes how a message shows the receiver: main, a special constant,
  # `#<Foo:0x...>` when it has a singleton class, else `an instance of Foo`.
  #: (ptr, value) -> value
  def zr_buf_receiver(b, recv)
    if recv == zr_global(G_MAIN)
      zr_buf_push(b, Machine.bytes("main"), 4)
    elsif recv == QNIL
      zr_buf_push(b, Machine.bytes("nil"), 3)
    elsif recv == QTRUE
      zr_buf_push(b, Machine.bytes("true"), 4)
    elsif recv == QFALSE
      zr_buf_push(b, Machine.bytes("false"), 5)
    elsif !zr_special_p(recv) && (zr_type(recv) == T_CLASS || zr_type(recv) == T_MODULE)
      zr_buf_push(b, zr_type(recv) == T_CLASS ? Machine.bytes("class ") : Machine.bytes("module "), zr_type(recv) == T_CLASS ? 6 : 7)
      s = zr_own_module_name(recv)
      if s == QNIL
        s = zr_inspect(recv)
      end
      return s if s == QUNDEF
      zr_buf_str(b, s)
    elsif !zr_special_p(recv) && zr_singleton_p(RBasic[recv].klass)
      zr_buf_obj_head(b, recv)
      zr_buf_byte(b, 62)
    else
      zr_buf_push(b, Machine.bytes("an instance of "), 15)
      s = zr_own_module_name(zr_real_class(recv))
      if s == QNIL
        zr_buf_class_of(b, recv)
      else
        zr_buf_str(b, s)
      end
    end
    Machine.value(QNIL)
  end

  # name_err_mesg_receiver_name: the String a program's own `name` gives
  # for a class or a module, or nil where the core's `name` answers, the
  # call raises, or it gives no String.
  #: (value) -> value
  def zr_own_module_name(mod)
    e = zr_find_method(zr_class_of(mod), Machine.id(:name))
    if e == 0 || MEntry[e].core != 0
      return Machine.value(QNIL)
    end
    s = zr_send(mod, Machine.id(:name), 0, 0)
    if s == QUNDEF
      Task[zr_task()].pending = Machine.value(QNIL)
      return Machine.value(QNIL)
    end
    if zr_special_p(s) || zr_type(s) != T_STRING
      return Machine.value(QNIL)
    end
    s
  end

  # Whether a call from the top frame can call `e` with `mode`. `mode` is 0
  # for an implicit or self receiver, 2 for an explicit receiver, and 3 for
  # `public_send` (its caller is the frame below its own). A private method
  # needs an implicit receiver. A protected method needs a caller whose
  # self is an instance of the owner. Returns 0, or the visibility that
  # stopped the call.
  #: (ptr, word) -> word
  def zr_visibility_refused(e, mode)
    mode = mode & SEND_MODE
    if mode < 2 || MEntry[e].vis == VIS_PUBLIC
      return 0
    end
    if MEntry[e].vis == VIS_PROTECTED && mode != 3
      owner = FrameMeta[MEntry[e].meta].owner
      # A refinement's protected method checks the class it refines.
      if !zr_special_p(owner) && zr_type(owner) == T_MODULE && ClassExt[RClass[owner].ext].refined != QNIL
        owner = ClassExt[RClass[owner].ext].refined
      end
      caller = Task[zr_task()].top
      if caller != 0 && zr_is_a(Frame[caller].self, owner)
        return 0
      end
    end
    MEntry[e].vis
  end

  # A send from the core library, to a name outside the protocol that
  # CRuby's C code sends by name. It finds the core library's own method on
  # a class that the runtime made, also when the program redefines the
  # method (zr_find_core_method).
  SEND_CORE = 8
  SEND_MODE = 7
  # A send written under `using`. The site sets its own active
  # refinements on the task before each send (the lowering's `activate`,
  # inline), and clears them after. Thus at that site the lookup result
  # depends only on the class and the stamp, and its cache entries can
  # keep it. The site checks its cache entry and takes an operator's fast
  # path, as any site does. A refinement's definition increments the
  # stamp, as any definition does, and closes the gate of the name that it
  # refines (zr_method_add_row). A `using` also increments the stamp.
  SEND_USING = 16

  # `argv` points at `argc` Values that the caller keeps rooted. `mode` is
  # 0 for an implicit or self receiver, 1 for a bare identifier, 2 for an
  # explicit receiver, plus SEND_CORE for a send from the core library. A
  # builtin runs under a frame that this pushes, so a backtrace shows it.
  # A compiled method pushes its own frame. `cc` is the send site's cache
  # entry (cache.rb), which gets the result, or 0 for a send without one.
  #: (ptr, value, word, word, ptr, word, value) -> value
  def zr_dispatch(cc, recv, mid, argc, argv, mode, blk)
    kw = zr_kw_take()
    klass = zr_box_view(zr_class_of(recv))
    e = 0
    if zr_imports_running_p()
      e = zr_imported_refined_method(recv, mid)
    end
    refined = zr_using_toplevel_refine()
    if e == 0 && (mode & SEND_CORE) != 0 && zr_core_class_p(klass) && ClassExt[RClass[klass].ext].boxed == QNIL
      e = zr_find_core_method(klass, mid)
    end
    if e == 0
      e = zr_find_method(klass, mid)
    end
    if refined && (e == 0 || zr_visibility_refused(e, mode) != 0)
      Task[zr_task()].refine = Machine.value(QNIL)
    end
    if e == 0
      how = mode & SEND_MODE
      return zr_method_missing(recv, mid, argc, argv, blk, kw, how == 1 ? MISS_VCALL : (how == 0 ? MISS_IMPLICIT : MISS_EXPLICIT))
    end
    vis = zr_visibility_refused(e, mode)
    if vis != 0
      return zr_method_missing(recv, mid, argc, argv, blk, kw, vis == VIS_PRIVATE ? MISS_PRIVATE : MISS_PROTECTED)
    end
    # `public_send` runs a visibility copy as CRuby's vm_call0 runs a
    # zsuper entry: with no method above it, the miss is a super's.
    if (mode & SEND_MODE) == 3 && MEntry[e].kind == KIND_MISSING && MEntry[e].from != QNIL
      return zr_method_missing(recv, mid, argc, argv, blk, kw, MISS_SUPER)
    end
    if zr_trace_sends_p() && (mode & SEND_CORE) == 0 && zr_trace_c_caller_p()
      if zr_trace_ruby_entry_p(e)
        return zr_trace_send_invoke(e, recv, mid, argc, argv, blk, kw, TRACE_CALL)
      end
      if zr_trace_c_entry_p(e)
        return zr_trace_send_invoke(e, recv, mid, argc, argv, blk, kw, TRACE_C_CALL)
      end
    end
    if cc != 0
      zr_call_cache_fill(cc, klass, e, mid, mode, argc)
    end
    r = zr_invoke(e, recv, argc, argv, blk, kw)
    # A site activates refinements for this send only: for the lookup, and
    # for a builtin such as `send` or `respond_to?` that uses them. A site
    # that checks its own cache entry never uses them.
    Task[zr_task()].refine = Machine.value(QNIL)
    r
  end

  # `super`: calls the next method with the frame's method name, after the
  # frame's owner in the receiver's ancestor list. The frame's block goes
  # to the callee unless `blk` is a different block. In a method from
  # `define_method`, the owner is the method entry's owner, and the name is
  # the name of the definition. An alias keeps that name (`orig`), as a
  # def's frame keeps the def's name.
  #: (ptr, ptr, word, ptr, value) -> value
  def zr_super(cc, rec, argc, argv, blk)
    if blk == QNIL
      return zr_super_call(cc, rec, argc, argv, blk)
    end
    before = zr_unwarned_call_from(rec)
    r = zr_super_call(cc, rec, argc, argv, blk)
    zr_unwarned_call_end(before)
    r
  end

  #: (ptr, ptr, word, ptr, value) -> value
  def zr_super_call(cc, rec, argc, argv, blk)
    recv = Frame[rec].self
    entry = zr_bmethod_entry(rec)
    if entry != 0
      owner = FrameMeta[MEntry[entry].meta].owner
      mid = MEntry[entry].orig
    else
      meta = zr_method_meta_of(rec)
      if meta == 0
        zr_kw_take()
        return zr_raise_msg(zr_global(G_NO_METHOD_ERROR), Machine.bytes("super called outside of method"), 30)
      end
      owner = FrameMeta[meta].owner
      mid = FrameMeta[meta].name
    end
    k = zr_super_from(rec, recv, owner, entry != 0)
    checked = zr_super_self_check(rec, recv, owner, k, entry != 0)
    if checked == QUNDEF
      zr_kw_take()
      return checked
    end
    # The site's cache entry is valid for the node and name that it was
    # filled for, under the method stamp, as for a send. The callee reads
    # the keywords that the site set.
    t = zr_task()
    traced = zr_trace_sends_p() && zr_trace_program_frame_p(rec)
    if cc != 0 && !traced && k != QNIL && SuperCache[cc].node == k && SuperCache[cc].mid == mid && SuperCache[cc].stamp == Machine.load64(Machine.static(:mcache_stamp, 8), 0) && Task[t].refine == QNIL
      return Method.call(SuperCache[cc].fn, recv, argc, argv, SuperCache[cc].entry, blk, SuperCache[cc].found)
    end
    kw = zr_kw_take()
    e = 0
    refined = false
    if k != QNIL && zr_type(k) == T_MODULE && ClassExt[RClass[k].ext].refined != QNIL
      # `super` in a refined method finds the method that the refinement
      # overrides (zr_refined_super_search).
      e = zr_refined_super_search(ClassExt[RClass[k].ext].refined, mid)
      refined = true
    elsif k != QNIL
      e = zr_find_method(RClass[k].superclass, mid)
    end
    # vm_call_super: with no method above, the receiver's method_missing
    # gets the call (MISSING_SUPER).
    if e == 0
      return zr_method_missing(recv, mid, argc, argv, blk, kw, MISS_SUPER)
    end
    if cc != 0 && !refined && Task[t].refine == QNIL && Machine.load64(Machine.static(:mcache_mode, 8), 0) == 0 && !zr_imports_running_p() && MEntry[e].imported == 0
      SuperCache[cc].node = k
      SuperCache[cc].mid = mid
      SuperCache[cc].stamp = Machine.load64(Machine.static(:mcache_stamp, 8), 0)
      SuperCache[cc].entry = e
      SuperCache[cc].found = zr_entry_found(e)
      SuperCache[cc].fn = zr_entry_fn(e)
    end
    # A super from the program into a C method fires :c_call and
    # :c_return, with the class that has the method.
    if traced && zr_trace_c_entry_p(e)
      above = Task[t].found
      if !zr_special_p(above) && zr_type(above) == T_ICLASS
        above = RClass[above].attached
      end
      r = zr_trace_owned_invoke(e, above, recv, argc, argv, blk, kw, TRACE_C_CALL)
    else
      r = zr_invoke(e, recv, argc, argv, blk, kw)
    end
    # The site activated the refinements for this super only.
    Task[t].refine = Machine.value(QNIL)
    r
  end

  # `super` in a refinement's method: the refined class's own methods
  # first, up to its origin, with no refinement, because the refinement
  # would otherwise find itself. Above them, the refinements that the
  # super site uses apply, as search_refined_method goes on to the
  # superclass.
  #: (value, word) -> ptr
  def zr_refined_super_search(refined, mid)
    origin = zr_origin(refined)
    k = refined
    while k != QNIL
      e = zr_find_method_at(k, mid)
      if e != 0
        if MEntry[e].kind == KIND_UNDEF
          return 0
        end
        Task[zr_task()].found = k
        return e
      end
      if k == origin
        break
      end
      k = RClass[k].superclass
    end
    if RClass[origin].superclass == QNIL
      return 0
    end
    zr_find_method(RClass[origin].superclass, mid)
  end

  # vm_search_super_method: `self` must still be a kind of the method's
  # class, which an instance_eval in the method can change. That class is
  # the node `k` where the method was found (a clone's singleton class or
  # a dup's copy, which the meta's owner is not), else the owner. The
  # message names a module's method by the class that includes it. A
  # refinement, and a module's method that bind_call runs (its class is
  # the module, not a proxy), make no check. Returns undef after the
  # raise, else nil.
  #: (ptr, value, value, value, bool) -> value
  def zr_super_self_check(rec, recv, owner, k, bmethod)
    cls = k == QNIL ? owner : k
    if zr_type(cls) == T_ICLASS
      cls = RClass[cls].attached
    end
    # The common case first: it needs no walk of the frames.
    if zr_is_a(recv, cls)
      return Machine.value(QNIL)
    end
    defined = Machine.value(QNIL)
    if zr_type(cls) == T_MODULE
      if ClassExt[RClass[cls].ext].refined != QNIL || bmethod
        return Machine.value(QNIL)
      end
      defined = zr_frame_defined(rec)
      if defined == QNIL || zr_type(defined) != T_ICLASS
        return Machine.value(QNIL)
      end
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    # Both classes show through their own to_s, as %PRIsVALUE writes them.
    zr_buf_push(b, Machine.bytes("self has wrong type to call super in this context: "), 51)
    shown = zr_buf_class_shown(b, recv)
    if shown == QUNDEF
      zr_buf_free(b)
      return shown
    end
    zr_buf_push(b, Machine.bytes(" (expected "), 11)
    shown = zr_obj_as_string(zr_type(cls) == T_MODULE ? zr_super_includer(rec, defined) : cls)
    if shown == QUNDEF
      zr_buf_free(b)
      return shown
    end
    zr_buf_str(b, shown)
    zr_buf_byte(b, 41)
    zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end

  # The class whose ancestor list holds the module proxy `node`, read from
  # the receiver that the method frame was called on (RCLASS_INCLUDER).
  #: (ptr, value) -> value
  def zr_super_includer(rec, node)
    meta = zr_method_meta_of(rec)
    r = rec
    while r != 0 && Frame[r].meta != meta
      r = Frame[r].prev
    end
    k = zr_class_of(Frame[r].self)
    last = k
    while k != QNIL && k != node
      if zr_type(k) != T_ICLASS
        last = k
      end
      k = RClass[k].superclass
    end
    last
  end

  # Returns the ancestor list node where the lookup found the frame's
  # method (through its blocks). Returns nil for a frame that the kernel
  # pushed.
  #: (ptr) -> value
  def zr_frame_defined(rec)
    meta = zr_method_meta_of(rec)
    r = rec
    while r != 0 && Frame[r].meta != meta
      r = Frame[r].prev
    end
    if r == 0
      return Machine.value(QNIL)
    end
    Frame[r].defined
  end

  # Returns the method entry of the `define_method` method that the frame
  # runs in, or 0. An instance_eval in that method pushes its own cref
  # in front of the method's.
  #: (ptr) -> ptr
  def zr_bmethod_entry(rec)
    cref = Frame[rec].cref
    while cref != QNIL && RCref[cref].eval != 0
      if RCref[cref].entry != 0
        return RCref[cref].entry
      end
      cref = RCref[cref].next
    end
    0
  end

  # Returns the meta of the def that contains the frame, through its
  # blocks and evals. Returns 0 in a class body or at the top level.
  #: (ptr) -> ptr
  def zr_method_meta_of(rec)
    meta = Frame[rec].meta
    while (FrameMeta[meta].kind == KIND_BLOCK || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].kind == KIND_EVAL) && FrameMeta[meta].parent != 0
      meta = FrameMeta[meta].parent
    end
    if FrameMeta[meta].kind != KIND_DEF && FrameMeta[meta].kind != KIND_BUILTIN
      return 0
    end
    meta
  end

  # `defined?(super)`: whether a method is after this frame's owner.
  #: (ptr) -> value
  def zr_super_defined(rec)
    entry = zr_bmethod_entry(rec)
    if entry != 0
      owner = FrameMeta[MEntry[entry].meta].owner
      mid = MEntry[entry].orig
    else
      meta = zr_method_meta_of(rec)
      if meta == 0
        return Machine.value(QFALSE)
      end
      owner = FrameMeta[meta].owner
      mid = FrameMeta[meta].name
    end
    k = zr_super_from(rec, Frame[rec].self, owner, entry != 0)
    if k == QNIL
      return Machine.value(QFALSE)
    end
    zr_bool(zr_find_method(RClass[k].superclass, mid) != 0)
  end

  # Returns the node after which a `super` in the frame continues. This is
  # the method frame's defining node when that node represents `owner` (a
  # module included twice has two nodes). Otherwise it is the first node
  # of `owner` in the receiver's ancestor list. Returns nil when there is
  # none. A method from `define_method` (`bmethod`) runs a block whose
  # lexical def is not its method, so only its owner counts.
  #: (ptr, value, value, bool) -> value
  def zr_super_from(rec, recv, owner, bmethod)
    k = bmethod ? Machine.value(QNIL) : zr_frame_defined(rec)
    # A class with a prepended module holds its methods in its origin. An
    # alias made before the prepend still names the class itself.
    if k != QNIL && zr_type(k) == T_CLASS
      k = zr_origin(k)
    end
    # A plain module (not a proxy in a list) is where a bound method was
    # called from (`bind_call`): the search starts from the receiver.
    if k != QNIL && !(zr_type(k) == T_MODULE && ClassExt[RClass[k].ext].refined == QNIL)
      return k
    end
    k = zr_class_of(recv)
    while k != QNIL && !(k == owner || (zr_type(k) == T_ICLASS && RClass[k].attached == owner))
      k = RClass[k].superclass
    end
    # A module's method bound to an object whose class does not include
    # the module (`bind_call`) goes on from the object's class, as through
    # the proxy that umethod_bind puts on it (rb_include_class_new).
    if k == QNIL && !zr_special_p(owner) && zr_type(owner) == T_MODULE
      k = zr_alloc(T_ICLASS, owner, RClass.size)
      RClass[k].name = Machine.value(QNIL)
      RClass[k].superclass = zr_class_of(recv)
      RClass[k].ext = RClass[owner].ext
      RClass[k].attached = owner
      RClass[k].origin = Machine.value(QNIL)
    end
    k
  end

  # A bare `super` in a block. When the block runs as a method from
  # `define_method`, CRuby raises for implicit arguments, in all defs.
  #: (ptr) -> value
  def zr_zsuper_in_block(rec)
    if zr_bmethod_entry(rec) != 0
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly."), 125)
    end
    Machine.value(QNIL)
  end

  # A bare `super` outside a def. In a method from `define_method` it
  # raises the implicit-argument error. Elsewhere there is no method.
  #: (ptr) -> value
  def zr_zsuper_outside(rec)
    r = zr_zsuper_in_block(rec)
    return r if r == QUNDEF
    zr_raise_msg(zr_global(G_NO_METHOD_ERROR), Machine.bytes("super called outside of method"), 30)
  end

  # Calls through the method entry `e`. A compiled def gets the keywords
  # flag and pushes its own frame. A builtin runs under a frame that this
  # pushes.
  #: (ptr, value, word, ptr, value, word) -> value
  def zr_invoke(e, recv, argc, argv, blk, kw)
    kind = MEntry[e].kind
    # Proc#call gives the block the keyword word as it is, so a table
    # of no keywords still keeps a lone Array whole.
    if kw > 1 && kind != KIND_DEF && kind != KIND_BMETHOD && (MEntry[e].fn != Machine.addr(:zr_proc_call) || Machine.load64(kw, 0) != 0)
      argc = zr_kw_tab_in(kw, argc, argv)
      kw = zr_kw_hashed(kw)
    end
    if kind == KIND_DEF
      arity = MEntry[e].arity
      if arity >= 0
        # For a def with a fixed count, which declares no keywords, the
        # table's values are one Hash argument.
        given = kw > 1 ? argc - Machine.load64(kw, 0) + zr_kw_hashed(kw) : argc
        if given != arity
          return zr_wrong_arity_in(given, arity, e, recv)
        end
      end
      Task[zr_task()].kw = kw
      if MEntry[e].imported != 0
        return zr_imported_invoke(e, recv, argc, argv, blk)
      end
      return Method.call(MEntry[e].fn, recv, argc, argv, e, blk, zr_entry_found(e))
    end
    # An accessor has no frame, so its arity error comes from the caller.
    if MEntry[e].kind == KIND_ATTR_READER
      if argc != 0
        return zr_wrong_arity(argc, 0)
      end
      return zr_ivar_get(recv, Machine.word(MEntry[e].fn))
    end
    if MEntry[e].kind == KIND_ATTR_WRITER
      if argc != 1
        return zr_wrong_arity(argc, 1)
      end
      return zr_ivar_set(recv, Machine.word(MEntry[e].fn), Machine.value(Machine.load64(argv, 0)))
    end
    if MEntry[e].kind == KIND_STRUCT_AREF
      if argc != 0
        return zr_wrong_arity(argc, 0)
      end
      return zr_struct_get(recv, e)
    end
    if MEntry[e].kind == KIND_STRUCT_ASET
      if argc != 1
        return zr_wrong_arity(argc, 1)
      end
      return zr_struct_set(recv, e, Machine.value(Machine.load64(argv, 0)))
    end
    if MEntry[e].kind == KIND_FRAMELESS
      Task[zr_task()].kw = kw
      return Builtin.call(MEntry[e].fn, recv, argc, argv, Machine.value(QNIL), blk)
    end
    if MEntry[e].kind == KIND_BMETHOD
      Task[zr_task()].kw = kw
      return zr_bmethod_call(e, recv, argc, argv, blk)
    end
    if MEntry[e].kind == KIND_MISSING
      return zr_method_missing(recv, MEntry[e].mid, argc, argv, blk, kw, MISS_EXPLICIT)
    end
    rec = Machine.slot(Frame.size)
    t = zr_task()
    # A builtin can run Ruby that calls builtins again, with no compiled
    # frame between them. Thus its frame does the stack check of a
    # compiled prologue, before it links the frame.
    if Machine.word(rec) < Machine.word(Task[t].stack_limit)
      return zr_stack_overflow()
    end
    Frame[rec].prev = Task[t].top
    Frame[rec].meta = MEntry[e].meta
    Frame[rec].line = 0
    Frame[rec].serial = 0
    Frame[rec].self = recv
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = blk
    Frame[rec].nvalues = 0
    # The entry gives the name used in the call, which can be an alias. An
    # enumerator that the builtin returns records that name.
    Frame[rec].entry = e
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].defined = Machine.value(QNIL)
    Task[t].top = rec
    Task[t].kw = kw
    arity = MEntry[e].arity
    if arity >= 0 && argc != arity
      r = zr_wrong_arity(argc, arity)
    else
      r = Builtin.call(MEntry[e].fn, recv, argc, argv, Machine.value(QNIL), blk)
    end
    Task[t].kw = 0
    Task[t].top = Frame[rec].prev
    r
  end

  # Raises an arity error of a compiled method under that method's frame,
  # as CRuby's backtrace shows it.
  #: (word, word, ptr, value) -> value
  def zr_wrong_arity_in(given, expected, e, recv)
    rec = Machine.slot(Frame.size)
    t = zr_task()
    Frame[rec].prev = Task[t].top
    Frame[rec].meta = MEntry[e].meta
    Frame[rec].line = FrameMeta[MEntry[e].meta].line | (FrameMeta[MEntry[e].meta].node << 32)
    Frame[rec].serial = 0
    Frame[rec].self = recv
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = Machine.value(QNIL)
    Frame[rec].nvalues = 0
    Frame[rec].entry = e
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].defined = Machine.value(QNIL)
    Task[t].top = rec
    r = zr_wrong_arity(given, expected)
    Task[t].top = Frame[rec].prev
    r
  end

  # Returns the ancestor list node that a method's frame records as its
  # definition point. For an alias or a visibility copy, it is the source
  # node. Otherwise it is the node where the lookup found the method.
  #: (ptr) -> value
  def zr_entry_found(e)
    from = MEntry[e].from
    from != QNIL ? from : Task[zr_task()].found
  end

  # The kernel's own sends, which have no site and thus no cache entry.
  # Compiled Ruby sends through `zr_send_cached` (cache.rb).
  #: (value, word, word, ptr) -> value
  def zr_send(recv, mid, argc, argv)
    zr_dispatch(0, recv, mid, argc, argv, 0, Machine.value(QNIL))
  end

  #: (value, word, word, ptr, value) -> value
  def zr_send_blk(recv, mid, argc, argv, blk)
    zr_dispatch(0, recv, mid, argc, argv, 0, blk)
  end

  # `Hash.ruby2_keywords_hash`: a copy with the flag. The next function
  # checks for the flag.
  #: (value) -> value
  def zr_ruby2_hash_new(h)
    copy = zr_hash_new()
    zr_hash_update(copy, h)
    RBasic[copy].flags = RBasic[copy].flags | FL_RUBY2
    copy
  end

  # Marks `h` as a hash of keywords that a ruby2_keywords method passes on.
  #: (value) -> value
  def zr_ruby2_hash_mark(h)
    RBasic[h].flags = RBasic[h].flags | FL_RUBY2
    h
  end

  #: (value) -> value
  def zr_ruby2_hash_p(h)
    zr_bool(!zr_special_p(h) && zr_type(h) == T_HASH && (RBasic[h].flags & FL_RUBY2) != 0)
  end

  # Preemption. A green thread that only computes makes no blocking call,
  # so no other thread can run. Every safe point reads the poll word
  # (`zr_poll_slot`, next to the task word): a compiled loop's back edge,
  # a compiled method's entry, and the kernel's loops through
  # `zr_preempt`. The kernel acts at a safe point only when the word is
  # set. The timer thread sets it every 100 ms after a second thread starts
  # (`zr_os_poll_start`). A caught POSIX signal and a collection that
  # queued a finalizer also set it. Under wasm there is no timer thread,
  # so a count is the clock: compiled back edges decrement it, and the
  # kernel's loops decrement it here. Thread sets the receiver and message
  # when a second thread starts, so a one-thread program never yields to
  # the scheduler.
  PREEMPT_TICKS = 20_000

  #: (value, value) -> value
  def zr_preempt_arm(receiver, message)
    Machine.store64(Machine.static(:preempt_mid, 8), 0, zr_sym2id(message))
    Machine.store64(Machine.static(:preempt_to, 8), 0, Machine.word(receiver))
    zr_os_poll_start()
    Machine.value(QNIL)
  end

  # A forked child has no timer thread: fork copies only the thread that
  # called it. A child of a parent that had one starts its own.
  #: () -> value
  def zr_poll_after_fork
    started = Machine.static(:poll_started, 8)
    if Machine.load64(started, 0) != 0
      Machine.store64(started, 0, 0)
      zr_os_poll_start()
    end
    Machine.value(QNIL)
  end

  # Requests action at the next safe point, for a POSIX signal, a
  # finalizer, or the timer.
  #: () -> void
  def zr_poll_set
    Machine.store64(zr_poll_slot(), 0, 1)
  end

  # Whether a second thread started. Until then, each task is alone, and
  # IO does not need to call the scheduler before a system call.
  #: () -> value
  def zr_threaded
    zr_bool(Machine.load64(Machine.static(:preempt_to, 8), 0) != 0)
  end

  #: () -> value
  def zr_preempt
    count = Machine.static(:preempt_count, 8)
    n = Machine.load64(count, 0) - 1
    Machine.store64(count, 0, n)
    if n > 0 && Machine.load64(zr_poll_slot(), 0) == 0
      return Machine.value(QNIL)
    end
    zr_preempt_expired()
  end

  # Runs a requested safe point. It resets the poll word and the count,
  # and runs the handlers of POSIX signals that arrived. Then, if a
  # second thread set up preemption, it yields to the scheduler, which
  # runs the finalizers that a collection queued where a thread may
  # switch: a finalizer can wait for another thread. Else it runs them
  # here.
  #: () -> value
  def zr_preempt_expired
    Machine.store64(zr_poll_slot(), 0, 0)
    Machine.store64(Machine.static(:preempt_count, 8), 0, PREEMPT_TICKS)
    if zr_trap_check() == QUNDEF
      return Machine.value(QUNDEF)
    end
    mid = Machine.load64(Machine.static(:preempt_mid, 8), 0)
    if mid == 0
      return zr_finalizers_due()
    end
    zr_preempt_send(mid)
  end

  # Runs the free functions and the finalizers that a collection queued,
  # if any.
  #: () -> value
  def zr_finalizers_due
    zr_data_frees_run()
    if WeakList[zr_finalizer_queue()].len > 0
      return zr_finalizers_run()
    end
    Machine.value(QNIL)
  end

  # Yields to the scheduler through the receiver that Thread set. It never
  # does this while this task is already in one of those sends, because
  # the scheduler runs its own compiled Ruby, with back edges.
  #: (word) -> value
  def zr_preempt_send(mid)
    busy = Machine.static(:preempt_busy, 8)
    t = Machine.word(zr_task())
    if Machine.load64(busy, 0) == t
      return Machine.value(QNIL)
    end
    Machine.store64(busy, 0, t)
    r = zr_send(Machine.value(Machine.load64(Machine.static(:preempt_to, 8), 0)), mid, 0, Machine.ptr(0))
    Machine.store64(busy, 0, 0)
    r
  end

  # Whether `v` responds to `mid`, as rb_check_funcall decides before a
  # conversion calls it. If the program defines respond_to? and it returns
  # false, the result is false. If a method exists, the result is true.
  # Otherwise, if the program defines respond_to_missing? and it returns
  # true, the result is true and method_missing handles the call. Returns
  # QUNDEF when a hook raised.
  #: (value, word) -> value
  def zr_check_funcall(v, mid)
    klass = zr_class_of(v)
    asks = zr_find_method(klass, Machine.id(:respond_to?))
    if asks != 0 && MEntry[asks].core == 0
      argv = Machine.slot(16)
      Machine.store64(argv, 0, Machine.word(v))
      Machine.store64(argv, 8, Machine.word(zr_sym(mid)))
      r = zr_send(zr_global(G_KERNEL), Machine.id(:respond_to_asked), 2, argv)
      return r if r == QUNDEF
      if r == QNIL || r == QFALSE
        return Machine.value(QFALSE)
      end
      # The program said yes: the call goes ahead, to method_missing if
      # no method answers, as check_funcall_respond_to lets it.
      return Machine.value(QTRUE)
    end
    if zr_find_method(klass, mid) != 0
      return Machine.value(QTRUE)
    end
    missing = zr_find_method(klass, Machine.id(:respond_to_missing?))
    if missing == 0 || MEntry[missing].core != 0
      return Machine.value(QFALSE)
    end
    argv = Machine.slot(16)
    Machine.store64(argv, 0, Machine.word(zr_sym(mid)))
    Machine.store64(argv, 8, QTRUE)
    r = zr_send(v, Machine.id(:respond_to_missing?), 2, argv)
    return r if r == QUNDEF
    zr_bool(r != QNIL && r != QFALSE)
  end

  # rb_check_funcall for an implicit conversion (`to_str`, `to_int`):
  # true with the result at `out`, false when `v` does not convert, or
  # undef for a raise. A program's respond_to? or method_missing answers,
  # as in ruby; a method_missing that raises NoMethodError converts nothing.
  #: (value, word, ptr) -> value
  def zr_convert_call(v, mid, out)
    klass = zr_class_of(v)
    found = zr_find_method(klass, mid) != 0
    unless found
      asks = zr_find_method(klass, Machine.id(:respond_to?))
      missing = zr_find_method(klass, Machine.id(:method_missing))
      # The core's own methods alone: nothing to ask, as before.
      if (asks == 0 || MEntry[asks].core != 0) && (missing == 0 || MEntry[missing].core != 0)
        return Machine.value(QFALSE)
      end
      responds = zr_check_funcall(v, mid)
      return responds if responds == QUNDEF
      if responds != QTRUE
        answers = zr_find_method(klass, Machine.id(:respond_to_missing?))
        if (answers != 0 && MEntry[answers].core == 0) || (asks != 0 && MEntry[asks].core == 0)
          return Machine.value(QFALSE)
        end
      end
      if missing == 0 || MEntry[missing].core != 0
        return Machine.value(QFALSE)
      end
    end
    r = zr_send(v, mid, 0, 0)
    if r == QUNDEF
      exc = zr_rescuable()
      if !found && exc != QUNDEF && zr_is_a(exc, zr_global(G_NO_METHOD_ERROR))
        Task[zr_task()].pending = Machine.value(QNIL)
        return Machine.value(QFALSE)
      end
      return r
    end
    Machine.store64(out, 0, Machine.word(r))
    Machine.value(QTRUE)
  end

  # rb_check_funcall with no arguments: the result of `name`, or nil when
  # `v` does not respond to it. As in ruby, a method_missing of the
  # program answers when respond_to_missing? and respond_to? are the
  # core's, and a NoMethodError from it means that `v` does not respond
  # (check_funcall_missing). Works on a BasicObject, which has neither
  # respond_to? nor is_a?. Returns QUNDEF when a call raised.
  #: (value, value) -> value
  def zr_check_call(v, name)
    mid = zr_sym2id(name)
    responds = zr_check_funcall(v, mid)
    return responds if responds == QUNDEF
    klass = zr_class_of(v)
    missing = zr_find_method(klass, Machine.id(:method_missing))
    if responds == QTRUE
      # check_funcall_missing: with no method and the core's
      # method_missing, the call does not happen.
      if zr_find_method(klass, mid) == 0 && (missing == 0 || MEntry[missing].core != 0)
        return Machine.value(QNIL)
      end
      return zr_send(v, mid, 0, 0)
    end
    if missing == 0 || MEntry[missing].core != 0
      return Machine.value(QNIL)
    end
    answers = zr_find_method(klass, Machine.id(:respond_to_missing?))
    asks = zr_find_method(klass, Machine.id(:respond_to?))
    if (answers != 0 && MEntry[answers].core == 0) || (asks != 0 && MEntry[asks].core == 0)
      return Machine.value(QNIL)
    end
    r = zr_send(v, mid, 0, 0)
    if r == QUNDEF
      exc = zr_rescuable()
      if exc != QUNDEF && zr_is_a(exc, zr_global(G_NO_METHOD_ERROR))
        Task[zr_task()].pending = Machine.value(QNIL)
        return Machine.value(QNIL)
      end
    end
    r
  end
end
