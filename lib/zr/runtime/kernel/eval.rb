# Runs a block with a different self: `instance_eval`, `class_eval`,
# `Class.new { }`, and the methods that `define_method` makes from a
# block.
#
# The kernel copies the block's Proc with the new self and pushes a cref
# for the eval. A `def` in the block defines its method on that cref.
# Constant and class variable lookups also go through it (see RCref).

module Zr::Kern
  # A method whose body is a block. The method entry's `cref` slot
  # contains the Proc, and a call runs it as a lambda with the receiver as
  # self. The call allocates nothing: the body's image goes on the stack
  # with the receiver as self (`zr_bmethod_call`). It uses a cref that the
  # entry makes one time and keeps (`zr_bmethod_cref`).
  KIND_BMETHOD = 8

  #: (value, value, value) -> value
  def zr_proc_under(p, self_, cref)
    blk = zr_block_proc(RProc[p].blk)
    copy = zr_alloc(T_PROC, zr_global(G_PROC), RProc.size)
    zr_memcpy(Machine.ptr(copy) + RBasic.size, Machine.ptr(p) + RBasic.size, RProc.size - RBasic.size)
    RProc[copy].blk = blk
    RProc[copy].self = self_
    RProc[copy].cref = cref
    copy
  end

  # Runs the block with `self_` as self and `klass` as the definee.
  #: (value, value, value, word, ptr) -> value
  def zr_yield_under(blk, self_, klass, argc, argv)
    # A native Proc (of a Method, a Symbol or an enumerator stage) keeps
    # its data where a block keeps its self, and runs as it is: the self
    # of instance_exec does not reach it.
    if RProc[blk].meta == 0
      return Block.call(RProc[blk].fn, blk, argc, argv, Machine.value(QNIL))
    end
    c = zr_cref_push_eval(klass, RProc[blk].cref)
    # An object that can have a singleton class gets one only when the
    # block needs it, as in ruby's instance_exec.
    if klass == QUNDEF
      RCref[c].klass = Machine.value(QNIL)
      RCref[c].lazy = self_
    end
    # A value that cannot have a singleton class also cannot take a `def`,
    # as in CRuby's singleton_class_for_eval.
    if zr_singleton_refused_p(self_)
      RCref[c].eval = EVAL_NO_DEF
    end
    p = zr_proc_under(blk, self_, c)
    Block.call(RProc[p].fn, p, argc, argv, Machine.value(QNIL))
  end

  # Raises `no block given` for a call that needs a block and gets none.
  # instance_exec uses this text, not the text of `yield`.
  #: () -> value
  def zr_block_needed
    zr_raise_msg(zr_global(G_LOCAL_JUMP_ERROR), Machine.bytes("no block given"), 14)
  end

  # `Class#initialize(superclass) { }`, on a class that `Class#new` made
  # with no superclass. It sets the ancestor list, calls the `inherited`
  # hook, then runs the block with the class as self and as argument.
  #: (value, word, ptr, value, value) -> value
  def zr_class_initialize(recv, argc, argv, cref, blk)
    if RClass[recv].superclass != QNIL || recv == zr_global(G_BASIC_OBJECT)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("already initialized class"), 25)
    end
    if argc > 1
      return zr_wrong_arity_range(argc, 0, 1)
    end
    sup = zr_global(G_OBJECT)
    if argc > 0
      sup = Machine.value(Machine.load64(argv, 0))
      r = zr_check_inheritable(sup)
      return r if r == QUNDEF
      if RClass[sup].superclass == QNIL && sup != zr_global(G_BASIC_OBJECT)
        return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't inherit uninitialized class"), 33)
      end
    end
    RClass[recv].superclass = sup
    zr_methods_changed()
    zr_class_rank(recv)
    zr_make_metaclass(recv)
    r = zr_hook(sup, Machine.id(:inherited), recv)
    return r if r == QUNDEF
    if blk != QNIL
      slot = Machine.slot(8)
      Machine.store64(slot, 0, Machine.word(recv))
      r = zr_yield_under(blk, recv, recv, 1, slot)
      return r if r == QUNDEF
    end
    recv
  end

  #: (value, word, ptr, value, value) -> value
  def zr_module_initialize(recv, argc, argv, cref, blk)
    if blk != QNIL
      slot = Machine.slot(8)
      Machine.store64(slot, 0, Machine.word(recv))
      r = zr_yield_under(blk, recv, recv, 1, slot)
      return r if r == QUNDEF
    end
    Machine.value(QNIL)
  end

  # `class_eval { }` and `module_eval { }`: run the block with the module
  # as self and as argument. `class_exec` passes its arguments instead.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_class_eval(recv, argc, argv, cref, blk)
    if blk == QNIL
      if argc > 0
        return zr_unimplemented(zr_str_new(Machine.bytes("class_eval with a string"), 24))
      end
      return zr_wrong_arity_range(argc, 1, 3)
    end
    if argc != 0
      return zr_wrong_arity(argc, 0)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(recv))
    zr_yield_under(blk, recv, recv, 1, slot)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_mod_class_exec(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_block_needed()
    end
    zr_yield_under(blk, recv, recv, argc, argv)
  end

  # The class that gets a `def` inside `instance_eval`: the object's
  # singleton class, or the class of a special constant. For a value that
  # cannot have a singleton class, it returns the class, and the eval cref
  # refuses a `def`. `zr_eval_definee` is the same for a block, but
  # returns undef for an object whose singleton class is made only when
  # the block needs it.
  #: (value) -> value
  def zr_eval_definee(obj)
    if zr_special_p(obj) || zr_singleton_refused_p(obj)
      return zr_class_of(obj)
    end
    Machine.value(QUNDEF)
  end

  #: (value) -> value
  def zr_eval_class_of(obj)
    if zr_special_p(obj) || zr_singleton_refused_p(obj)
      return zr_class_of(obj)
    end
    zr_singleton_class(obj)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_instance_eval(recv, argc, argv, cref, blk)
    if blk == QNIL
      if argc > 0
        return zr_unimplemented(zr_str_new(Machine.bytes("instance_eval with a string"), 27))
      end
      # With no block and no string there is nothing to run. CRuby raises
      # an arity error for the arguments that it expects.
      return zr_wrong_arity_range(argc, 1, 3)
    end
    if argc != 0
      return zr_wrong_arity(argc, 0)
    end
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(recv))
    zr_yield_under(blk, recv, zr_eval_definee(recv), 1, slot)
  end

  #: (value, word, ptr, value, value) -> value
  def zr_obj_instance_exec(recv, argc, argv, cref, blk)
    if blk == QNIL
      return zr_block_needed()
    end
    zr_yield_under(blk, recv, zr_eval_definee(recv), argc, argv)
  end

  # `define_method(name) { }`, or with a Proc, Method or UnboundMethod in
  # place of the block. It defines a method whose body is the block's
  # body.
  #: (value, word, ptr, value, value) -> value
  def zr_mod_define_method(recv, argc, argv, cref, blk)
    zr_define_method_scoped(recv, argc, argv, blk, true)
  end

  # define_method's work. Where `scoped`, a call from the body of `recv`
  # takes its default visibility. define_singleton_method is not scoped:
  # its method is public, as rb_obj_define_method passes a public scope.
  #: (value, word, ptr, value, bool) -> value
  def zr_define_method_scoped(recv, argc, argv, blk, scoped)
    r = zr_class_modify_check(recv)
    return r if r == QUNDEF
    # rb_mod_define_method: the count of arguments is checked first.
    if argc == 0 || argc > 2
      return zr_wrong_arity_range(argc, 1, 2)
    end
    slot = Machine.slot(8)
    r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
    return r if r == QUNDEF
    mid = Machine.load64(slot, 0)
    body = zr_block_proc(blk)
    caller = Frame[Task[zr_task()].top].prev
    # The visibility comes from the caller's frame, not from the cref
    # that the call passes.
    home = scoped ? zr_cref_in_context(caller, recv) : Machine.value(QNIL)
    if argc > 1
      body = Machine.value(Machine.load64(argv, 8))
      if !zr_special_p(body) && zr_type(body) == T_METHOD
        e = Machine.ptr(RMethod[body].entry)
        owner = FrameMeta[MEntry[e].meta].owner
        if MEntry[e].meta != 0 && owner != recv && zr_type(owner) != T_MODULE && !zr_class_inherits(recv, owner)
          if zr_singleton_p(owner)
            return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't bind singleton method to a different class"), 48)
          end
          b = Machine.slot(Buf.size)
          zr_buf_init(b)
          zr_buf_push(b, Machine.bytes("bind argument must be a subclass of "), 36)
          zr_buf_class(b, owner)
          return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
        end
        # A bare `module_function` is a mode. The copy goes to both the
        # module and its singleton class, as a `def` does in that mode.
        modfn = home != QNIL && RCref[home].modfn != 0
        if modfn
          zr_method_copy(zr_singleton_class(recv), mid, e, zr_meta_owned_by(MEntry[e].meta, recv), VIS_PUBLIC, false)
        end
        owned = zr_meta_owned_by(MEntry[e].meta, recv)
        zr_method_copy(recv, mid, e, owned, zr_definition_vis(mid, home), false)
        # A frame shows the module that defined the method (#22197), but a
        # module's method on the module's own singleton class shows that
        # class ('Mod.m'), as location_original_module keeps it.
        if zr_singleton_p(recv) && RClass[recv].attached == owner
          MEntry[zr_find_method_at(zr_origin(recv), mid)].label = owned
        end
        r = zr_method_added(recv, mid)
        return r if r == QUNDEF
        if modfn
          r = zr_method_added(zr_singleton_class(recv), mid)
          return r if r == QUNDEF
        end
        return zr_sym(mid)
      end
      if zr_special_p(body) || zr_type(body) != T_PROC
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
        zr_buf_class_of(b, body)
        zr_buf_push(b, Machine.bytes(" (expected Proc/Method/UnboundMethod)"), 37)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
    elsif blk == QNIL
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("tried to create Proc object without a block"), 43)
    end
    # A Proc from Proc#refined has its refinements in its own cref, which
    # a method's body does not take (rb_mod_define_method).
    if RProc[body].fn == Machine.addr(:zr_refined_block)
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("can't define a method from a Proc with refinements"), 50)
    end
    r = zr_define_bmethod(recv, mid, zr_meta_site(caller, mid, recv), body, home)
    return r if r == QUNDEF
    zr_sym(mid)
  end

  # Returns a copy of `meta` with `owner` as its owner and the same name.
  # A backtrace shows this label for a method that
  # `define_method(name, method)` copies, as CRuby does.
  #: (ptr, value) -> ptr
  def zr_meta_owned_by(meta, owner)
    if meta == 0
      return 0
    end
    copy = zr_xmalloc(FrameMeta.size)
    zr_memcpy(copy, meta, FrameMeta.size)
    FrameMeta[copy].owner = zr_origin(owner)
    copy
  end

  # Returns the cref that gives the visibility for a `define_method` into
  # `mod`. It is the calling frame's cref only when that frame is the body
  # of `mod`. From any other place, the method is public.
  #: (ptr, value) -> value
  def zr_cref_in_context(frame, mod)
    cref = Frame[frame].cref
    if Frame[frame].self != mod || cref == QNIL || zr_cref_klass(cref) != mod
      return Machine.value(QNIL)
    end
    cref
  end

  # `define_singleton_method(name) { }`: the same as `define_method`, on
  # the singleton class.
  #: (value, word, ptr, value, value) -> value
  def zr_obj_define_singleton_method(recv, argc, argv, cref, blk)
    if zr_special_p(recv) && recv != QNIL && recv != QTRUE && recv != QFALSE
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
    end
    s = zr_singleton_class(recv)
    return s if s == QUNDEF
    zr_define_method_scoped(s, argc, argv, blk, false)
  end

  # Calls a method that `define_method` made. It runs the block as a
  # lambda with the receiver as self, and a `def` in it defines into the
  # owner. The body's image goes on the stack, as a send writes a block
  # literal (proc.rb). It is a descriptor for this call only, and its frame
  # is the GC root for the values that it refers to. The block given to
  # the call becomes the body's own block, and the frame keeps it in
  # `defined`. (A block frame's `blk` is the block of the method that
  # contains the body.)
  #: (ptr, value, word, ptr, value) -> value
  def zr_bmethod_call(e, recv, argc, argv, blk)
    zr_bmethod_fn(recv, argc, argv, e, blk, zr_entry_found(e))
  end

  # The same, as the function of a define_method entry that a compiled
  # site finds (`zr_entry_fn`). The site calls it directly, with no
  # second frame in between.
  #: (value, word, ptr, ptr, value, value) -> value
  def zr_bmethod_fn(recv, argc, argv, e, blk, found)
    # An entry has a coverage record only when the program measures
    # coverage, so most calls skip the call.
    if MEntry[e].cover != 0
      zr_coverage_method(e)
    end
    body = MEntry[e].cref
    if RProc[body].meta == 0
      # The Proc of a Symbol or a Method uses only its arguments.
      return Block.call(RProc[body].fn, body, argc, argv, blk)
    end
    # The copy is field by field: a libc call costs more.
    d = Machine.slot(RProc.size)
    p = Machine.value(d)
    RBasic[p].flags = T_PROC | FL_ALLOCATED | FL_STACK
    RBasic[p].klass = RBasic[body].klass
    RProc[p].fn = RProc[body].fn
    RProc[p].meta = RProc[body].meta
    RProc[p].env = RProc[body].env
    RProc[p].blk = RProc[body].blk
    RProc[p].serial = RProc[body].serial
    RProc[p].site = RProc[body].site
    RProc[p].ret_home = RProc[body].ret_home
    RProc[p].ret_serial = RProc[body].ret_serial
    RProc[p].spread = RProc[body].spread
    RProc[p].passed = RProc[body].passed
    RProc[p].self = recv
    if found != QNIL && !zr_special_p(found)
      RBasic[p].flags = RBasic[p].flags | FL_BMETHOD_RUN
      RProc[p].found = found
    end
    # The entry keeps its cref after the first call (`zr_bmethod_cref`).
    cref = zr_bmethod_cref_kept(e)
    if cref == QNIL || RCref[cref].entry != e
      cref = zr_bmethod_cref(e)
    end
    RProc[p].cref = cref
    RProc[p].lambda = 1
    RProc[p].home = 0
    if (Machine.load64(Machine.static(:trace_events, 8), 0) & (TRACE_CALL | TRACE_RETURN)) == 0
      return Block.call(RProc[p].fn, p, argc, argv, blk)
    end
    fired = zr_trace_bmethod(TRACE_CALL, e, recv, Machine.value(QNIL))
    return fired if fired == QUNDEF
    zr_trace_bmethod(TRACE_RETURN, e, recv, Block.call(RProc[p].fn, p, argc, argv, blk))
  end

  # Returns the cref for a define_method body. The entry makes it at its
  # first call and keeps it in its `ivar` word. The definee of a `def` in
  # the body is the class where the block was written, as in ruby, or the
  # owner for a block with no cref. The cref sits on top of the block's
  # own cref. It
  # refers to the method entry, so that `super`, a trace and a `break` can
  # find the method. A copy of the entry (in a Method, a saved entry or
  # another class) makes its own cref, because it is a different entry.
  #: (ptr) -> value
  def zr_bmethod_cref(e)
    c = zr_bmethod_cref_kept(e)
    if c != QNIL && RCref[c].entry == e
      return c
    end
    outer = RProc[MEntry[e].cref].cref
    definee = outer == QNIL ? FrameMeta[MEntry[e].meta].owner : zr_cref_klass(outer)
    c = zr_cref_push_eval(definee, outer)
    RCref[c].entry = e
    MEntry[e].ivar.index = Machine.word(c)
    # The cref goes into the entry's `ivar` word. The kernel subset
    # types it as a Word, so the compiler adds no write barrier as it does
    # for a Value field. The entry is in the owner's method table
    # (`zr_method_add_row` writes entries into `RClass.ext(klass)`), and
    # `zr_mark_entry` marks the cref from there. Thus the owner now refers
    # to this cref, and the barrier is on the owner.
    zr_write_barrier(FrameMeta[MEntry[e].meta].owner, c)
    c
  end

  # Returns the cref that a define_method entry made, or nil before its
  # first call.
  #: (ptr) -> value
  def zr_bmethod_cref_kept(e)
    kept = MEntry[e].ivar.index
    kept == 0 ? Machine.value(QNIL) : Machine.value(kept)
  end

  inline :zr_bmethod_cref_kept

  # Runs the body of a `refine` block with the holder module as self. A
  # `def` in it defines into the holder, and the block gets the holder as
  # its argument.
  #: (value, value) -> value
  def zr_refine_body(blk, holder)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(holder))
    zr_yield_under(blk, holder, holder, 1, slot)
  end
end
