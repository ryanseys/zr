# What a scope shows of itself: the calling frame, its locals by name,
# the Env that contains them, and the Binding that contains all of it.

module Zr::Kern
  # The frame that called eval. A runtime method calls the compiler, and
  # that method's frame is on top. Thus the next frame out is the frame
  # that contains the call.
  #: () -> ptr
  def zr_caller_frame
    Frame[Task[zr_task()].top].prev
  end

  # The frame that gives an eval its scope: the nearest frame written in
  # Ruby. A call through `Method#call`, `Enumerable#each` or a different
  # builtin has a frame with no locals, no cref and no block. The walk
  # skips such a frame, so `method(:eval).call("x")` reads the caller's
  # `x`. CRuby finds the same frame with rb_vm_get_ruby_level_next_cfp in
  # eval_string_with_cref, and uses all of that frame's block: its locals,
  # its ep, and its cref.
  #: () -> ptr
  def zr_eval_frame
    zr_frame_with_file(zr_caller_frame())
  end

  #: () -> value
  def zr_eval_cref
    Frame[zr_eval_frame()].cref
  end

  # A copy of `cref` for an eval string: a `private` with no names there
  # sets the copy's visibility, not the visibility of the code around it.
  #: (value) -> value
  def zr_cref_dup(cref)
    if cref == QNIL
      return cref
    end
    c = zr_cref_push(RCref[cref].klass, RCref[cref].next)
    RCref[c].vis = RCref[cref].vis
    RCref[c].modfn = RCref[cref].modfn
    RCref[c].eval = RCref[cref].eval
    RCref[c].entry = RCref[cref].entry
    RCref[c].lazy = RCref[cref].lazy
    c
  end

  #: () -> value
  def zr_eval_block
    Frame[zr_eval_frame()].blk
  end

  # `(eval at file:line)`: the name that ruby gives an eval with no file.
  #: () -> value
  def zr_eval_source_name
    rec = zr_eval_frame()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("(eval at "), 9)
    if rec != 0
      zr_buf_push(b, FrameMeta[Frame[rec].meta].file, FrameMeta[Frame[rec].meta].file_len)
      zr_buf_byte(b, 58)
      zr_buf_long(b, zr_frame_line(rec))
    end
    zr_buf_byte(b, 41)
    zr_buf_take(b)
  end

  # The cref for an eval of a string: the module on top of the scope of
  # the call. Thus a constant of the enclosing module stays visible, and
  # `Module.nesting` shows both modules.
  #: (value, value) -> value
  def zr_eval_cref_under(mod, outer)
    zr_cref_push(mod, outer)
  end

  # The cref of `obj.instance_eval(string)`: the object's singleton class,
  # made when the code first needs it, as CRuby's CREF_SINGLETON. Until
  # then a constant lookup reads the object's class there.
  #: (value, value) -> value
  def zr_eval_cref_lazy(obj, outer)
    # A value with no singleton class of its own (nil's is NilClass) gets
    # its class, which an eval pushed, so a class variable is found farther
    # out, as vm_get_cvar_base passes over it. A value that cannot have one
    # also cannot take a `def`.
    if zr_special_p(obj) || zr_singleton_refused_p(obj)
      c = zr_cref_push_eval(zr_class_of(obj), outer)
      if zr_singleton_refused_p(obj)
        RCref[c].eval = EVAL_NO_DEF
      end
      return c
    end
    k = RBasic[obj].klass
    c = zr_cref_push(k, outer)
    unless zr_singleton_p(k) && RClass[k].attached == obj
      RCref[c].klass = Machine.value(QNIL)
      RCref[c].lazy = obj
    end
    c
  end

  # The cref for a `load` with a wrap module: the module on top of the
  # toplevel cref. A def there is private, as at the toplevel.
  #: (value) -> value
  def zr_wrap_cref(mod)
    c = zr_cref_push(mod, zr_global(G_TOP_CREF))
    RCref[c].vis = VIS_PRIVATE
    c
  end

  # The names in a locals table, as symbols in slot order.
  #: (ptr) -> value
  def zr_local_names(table)
    a = zr_ary_new(0)
    if table != 0
      n = Machine.load64(table, 0)
      i = 0
      while i < n
        zr_ary_push(a, zr_sym(Machine.load64(table + 8 + (i * 8), 0)))
        i += 1
      end
    end
    a
  end

  # The Env of a frame's locals, as a cell, or nil if the frame keeps them
  # only in its frame record. A scope that calls eval or binding always
  # has an Env; `Hir::Locals.opens_locals?` makes sure of this.
  #: (ptr) -> value
  def zr_frame_env(rec)
    if FrameMeta[Frame[rec].meta].env == 0
      return Machine.value(QNIL)
    end
    zr_env_escape(Machine.value(Machine.load64(rec + Frame.size, 0)))
  end

  #: () -> value
  def zr_eval_env
    zr_frame_env(zr_eval_frame())
  end

  # The parameters of the method that contains the frame that called eval,
  # as Method#parameters returns them. The frame can be the method body,
  # or a block, an eval, or a block in an eval inside the method. Returns
  # nil outside a method.
  #: () -> value
  def zr_eval_parameters
    zr_meta_parameters(Frame[zr_eval_frame()].meta)
  end

  #: (value) -> value
  def zr_binding_parameters(b)
    zr_meta_parameters(RProc[b].meta)
  end

  #: (ptr) -> value
  def zr_meta_parameters(meta)
    if !zr_meta_in_method(meta)
      return Machine.value(QNIL)
    end
    while FrameMeta[meta].kind != KIND_DEF
      meta = FrameMeta[meta].parent
    end
    zr_param_rows(FrameMeta[meta].params, false)
  end

  #: (ptr) -> bool
  def zr_meta_in_method(meta)
    while meta != 0
      kind = FrameMeta[meta].kind
      if kind == KIND_DEF
        return true
      end
      if kind != KIND_BLOCK && kind != KIND_EVAL
        return false
      end
      meta = FrameMeta[meta].parent
    end
    false
  end

  # The locals of the scope of `meta` and, for a block or an eval, of the
  # scopes around it, innermost first. As rb_iseq_local_variables, it
  # also walks out of a class or module body.
  #: (ptr) -> value
  def zr_reachable_local_names(meta)
    out = zr_ary_new(0)
    while meta != 0
      table = FrameMeta[meta].locals
      if table != 0
        i = 0
        while i < Machine.load64(table, 0)
          zr_ary_push(out, zr_sym(Machine.load64(table + 8 + (i * 8), 0)))
          i += 1
        end
      end
      kind = FrameMeta[meta].kind
      if kind == KIND_CLASS || kind == KIND_MODULE
        meta = FrameMeta[meta].lexical
      elsif kind == KIND_BLOCK || kind == KIND_EVAL || kind == KIND_HIDDEN
        meta = FrameMeta[meta].parent
      else
        return out
      end
    end
    out
  end

  # The names of all scopes that the calling frame can reach, innermost
  # first: its own, then one Array for each Env along the parent list.
  #: () -> value
  def zr_eval_scopes
    out = zr_ary_new(0)
    env = zr_eval_env()
    while env != QNIL
      zr_ary_push(out, zr_local_names(REnv[env].names))
      env = REnv[env].parent
    end
    out
  end

  # `Kernel#binding` as the program calls it. A core method between
  # (`Method#call`, `UnboundMethod#bind_call`) is a caller with no Ruby
  # scope, and ruby raises for a C caller.
  #: () -> value
  def zr_ruby_binding
    rec = zr_caller_frame()
    kind = FrameMeta[Frame[rec].meta].kind
    if kind == KIND_BUILTIN || kind == KIND_HIDDEN
      return zr_raise_msg(zr_global(G_RUNTIME_ERROR), Machine.bytes("Cannot create Binding object for non-Ruby caller"), 48)
    end
    zr_binding_at(rec)
  end

  # `Kernel#local_variables`: the scope of the nearest frame written in
  # Ruby. A core method between is skipped, as ruby skips a C frame.
  #: () -> value
  def zr_local_binding
    zr_binding_at(zr_eval_frame())
  end

  # The scope of the running frame itself. The tree-walking interpreter's
  # toplevel for a required file (lib/zr/runtime/lib/zr/eval/interpreter_file.rb)
  # takes it: a new top-level scope each time it runs, with main as self.
  #: () -> value
  def zr_own_binding
    zr_binding_at(Task[zr_task()].top)
  end

  #: (ptr) -> value
  def zr_binding_at(rec)
    blk = zr_block_proc(Frame[rec].blk)
    b = zr_binding_of(Frame[rec].meta, zr_frame_env(rec), Frame[rec].self, Frame[rec].cref)
    RProc[b].blk = blk
    RProc[b].serial = zr_frame_line(rec)
    # The refinements in use where `binding` is written, which an eval in
    # the binding uses.
    using = zr_eval_using()
    if using != QNIL
      zr_hidden_set(b, zr_sym(Machine.id(:__using__)), using)
    end
    b
  end

  # The scope where a trap's String command runs, as rb_eval_cmd_call_kw
  # runs it (eval_string_with_cref): the innermost Ruby frame that a
  # backtrace shows, as a Binding whose self is `main`. nil when there is
  # none.
  #: (value) -> value
  def zr_trap_binding(main)
    rec = Task[zr_task()].top
    while rec != 0 && (!zr_frame_shown_p(rec) || zr_meta_native_p(Frame[rec].meta))
      rec = Frame[rec].prev
    end
    if rec == 0
      return Machine.value(QNIL)
    end
    b = zr_binding_at(rec)
    RProc[b].self = main
    # A method that keeps its locals only in its frame record (no Env)
    # lends the command a snapshot of them: the command reads them, as the
    # interrupted frame's own locals, and its writes stay in the snapshot.
    meta = Frame[rec].meta
    if RProc[b].env == QNIL && FrameMeta[meta].env == 0 && FrameMeta[meta].kind == KIND_DEF && FrameMeta[meta].locals != 0
      table = FrameMeta[meta].locals
      n = Machine.load64(table, 0)
      env = zr_env_new(Machine.value(QNIL), n, table)
      zr_memcpy(REnv[env].slots, rec + Frame.size, n * 8)
      zr_write_barrier_all(env)
      RProc[b].env = env
      zr_write_barrier(b, env)
    end
    b
  end

  # The `using` entry in force at the eval or binding call that runs now,
  # as an Integer, or nil. The call site writes it (`note_eval_using`);
  # this reads it once.
  #: () -> value
  def zr_eval_using
    t = zr_task()
    id = Task[t].eval_using
    Task[t].eval_using = 0
    using = id == 0 ? Machine.value(QNIL) : zr_fix(id - 1)
    if zr_special_p(zr_global(G_USING_TOPLEVEL))
      return using
    end
    zr_using_latest(using, Frame[zr_eval_frame()].meta)
  end

  # The `using` entry that an eval in `binding` starts under: the one in
  # use where the Binding was made, or a later one that an eval's `using`
  # left for its toplevel.
  #: (value) -> value
  def zr_binding_using_m(binding)
    zr_using_latest(zr_hidden_get(binding, zr_sym(Machine.id(:__using__))), RProc[binding].meta)
  end

  # `Proc#binding`: the scope where the block was written, which the Proc
  # already contains. The line is the block's line, because a Proc has no
  # line.
  #: (value) -> value
  def zr_proc_binding(p)
    # proc_binding of a Method's Proc: an empty scope (an empty iseq in
    # CRuby) whose self is the method's receiver.
    if RProc[p].fn == Machine.addr(:zr_method_block)
      base = Machine.static(:method_binding_meta, FrameMeta.size)
      FrameMeta[base].kind = KIND_TOP
      FrameMeta[base].owner = Machine.value(QNIL)
      # Its source_location is where the method is defined, as
      # proc_binding reads the method's iseq, and "(binding)" line 1 for a
      # builtin, which has none.
      defined = zr_method_meta(Machine.ptr(RMethod[RProc[p].self].entry))
      meta = zr_xmalloc(FrameMeta.size)
      zr_memcpy(meta, base, FrameMeta.size)
      line = 1
      # A core method has no file of its own: CRuby writes most in C.
      if defined == 0 || FrameMeta[defined].file_len == 0
        FrameMeta[meta].file = Machine.bytes("(binding)")
        FrameMeta[meta].file_len = 9
      else
        FrameMeta[meta].file = FrameMeta[defined].file
        FrameMeta[meta].file_len = FrameMeta[defined].file_len
        line = FrameMeta[defined].line
      end
      # Its constants are the method's own: a def's cref (vm_cref_new_toplevel
      # otherwise).
      entry = Machine.ptr(RMethod[RProc[p].self].entry)
      scope = zr_global(G_TOP_CREF)
      if MEntry[entry].kind == KIND_DEF && MEntry[entry].cref != QNIL
        scope = MEntry[entry].cref
      end
      b = zr_binding_of(meta, Machine.value(QNIL), RMethod[RProc[p].self].recv, scope)
      RProc[b].serial = line
      return b
    end
    # The core's anonymous Procs (curry, Hash#to_proc) are C functions in
    # CRuby, and have no binding either.
    if RProc[p].meta == 0 || RProc[p].meta == zr_anonymous_meta() || RProc[p].meta == zr_anonymous_meta1()
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("Can't create Binding from C level Proc"), 38)
    end
    if (RBasic[p].flags & FL_ISOLATED) != 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("Can't create Binding from isolated Proc"), 39)
    end
    zr_proc_scope(p)
  end

  # The scope of a Proc written in Ruby, also for an isolated Proc.
  # Ractor.shareable_proc reads a block's outer locals from it, as CRuby
  # reads its env.
  #: (value) -> value
  def zr_proc_scope(p)
    b = zr_binding_of(RProc[p].meta, RProc[p].env, RProc[p].self, RProc[p].cref)
    RProc[b].blk = RProc[p].blk
    RProc[b].serial = FrameMeta[RProc[p].meta].line
    b
  end

  # The tree-walking interpreter (lib/zr/eval/interpreter/tree.rb) reads the
  # frame that called eval through its Binding, where compiled eval code
  # has the frame itself.

  # The `$~` and `$_` cell of the Binding's frame: the nearest running
  # frame of its scope, or a cell of its own when the frame has
  # returned. A block's cell is its method's.
  #: (value) -> value
  def zr_binding_svars(b)
    rec = Task[zr_task()].top
    while rec != 0 && Frame[rec].meta != RProc[b].meta
      rec = Frame[rec].prev
    end
    home = rec
    if rec != 0
      home = zr_backref_home_from(rec)
    end
    if home == 0
      cell = zr_ary_new(2)
      zr_ary_push(cell, Machine.value(QNIL))
      zr_ary_push(cell, Machine.value(QNIL))
      return cell
    end
    zr_svars(home)
  end

  # `return` in a string evaluated in the Binding's scope: it returns from
  # the scope's method, or raises LocalJumpError, as zr_return_here does
  # for compiled eval code.
  #: (value, value) -> value
  def zr_binding_return(b, v)
    zr_return_scope(Task[zr_task()].top, RProc[b].meta, v)
  end

  # The name and the owner of the method that holds the Binding's scope,
  # through its blocks, or nil outside a method.
  #: (value) -> value
  def zr_binding_method(b)
    meta = RProc[b].meta
    while meta != 0 && (FrameMeta[meta].kind == KIND_BLOCK || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].kind == KIND_EVAL)
      meta = FrameMeta[meta].parent
    end
    if meta == 0 || FrameMeta[meta].kind != KIND_DEF
      return Machine.value(QNIL)
    end
    out = zr_ary_new(2)
    zr_ary_push(out, zr_sym(FrameMeta[meta].name))
    zr_ary_push(out, FrameMeta[meta].owner)
    out
  end

  # `Module.nesting` under `cref`: its modules, innermost first, without
  # the crefs of evals.
  #: (value) -> value
  def zr_cref_nesting(cref)
    out = zr_ary_new(4)
    c = cref
    while c != QNIL && c != zr_global(G_TOP_CREF)
      if RCref[c].eval == 0
        zr_ary_push(out, zr_cref_klass(c))
      end
      c = RCref[c].next
    end
    out
  end

  #: (ptr, value, value, value) -> value
  def zr_binding_of(meta, env, self_, cref)
    b = zr_alloc(T_PROC, zr_core_class(Machine.id(:Binding)), RProc.size)
    RProc[b].fn = 0
    RProc[b].meta = meta
    RProc[b].env = env
    RProc[b].self = self_
    RProc[b].cref = cref
    RProc[b].blk = Machine.value(QNIL)
    RProc[b].home = 0
    RProc[b].serial = 0
    RProc[b].site = 0
    RProc[b].ret_home = 0
    RProc[b].ret_serial = 0
    RProc[b].spread = 0
    RProc[b].lambda = 0
    RProc[b].passed = 0
    b
  end

  # The lexical scope of a Binding, where `binding.eval` runs its string.
  # The tree-walking interpreter reads it. The eval compiler gives the
  # Binding to `zr_binding_run` and does not read it.
  #: (value) -> value
  def zr_binding_cref(b)
    RProc[b].cref
  end

  #: (value) -> value
  def zr_binding_scopes(b)
    out = zr_ary_new(0)
    env = RProc[b].env
    while env != QNIL
      zr_ary_push(out, zr_local_names(REnv[env].names))
      env = REnv[env].parent
    end
    out
  end

  #: (value) -> value
  def zr_binding_receiver(b)
    RProc[b].self
  end

  #: (value) -> value
  def zr_binding_file(b)
    if RProc[b].site != 0
      return zr_str_new(Machine.bytes("<main>"), 6)
    end
    meta = RProc[b].meta
    if FrameMeta[meta].file_len == 0
      return Machine.value(QNIL)
    end
    zr_meta_path(meta)
  end

  #: (value) -> value
  def zr_binding_line(b)
    if RProc[b].site != 0
      return zr_fix(0)
    end
    zr_fix(RProc[b].serial)
  end

  #: (value, value, value) -> value
  def zr_binding_get(b, depth, index)
    zr_env_get(zr_env_up(RProc[b].env, zr_fix2long(depth)), zr_fix2long(index))
  end

  #: (value, value, value, value) -> value
  def zr_binding_set(b, depth, index, v)
    zr_env_set(zr_env_up(RProc[b].env, zr_fix2long(depth)), zr_fix2long(index), v)
    v
  end

  # Runs a loaded eval toplevel in a Binding, with its self, its cref and
  # its locals. The Binding keeps the Env where the string ran, so a name
  # that the string wrote becomes a local of the Binding.
  #: (value, value) -> value
  def zr_binding_run(code, b)
    e = zr_code_env(code, RProc[b].env)
    RProc[b].env = e
    # The string runs inside the Binding's scope, as CRuby makes the
    # binding's iseq its parent: `__method__` and a backtrace label read
    # the scope where the Binding was made.
    FrameMeta[Machine.ptr(zr_code_word(code, 1))].parent = RProc[b].meta
    # A Binding made in a box runs the string in that box, as Box#run
    # runs the box's own code (zr_box_stamp).
    box = FrameMeta[RProc[b].meta].box
    if Machine.word(box) != 0 && FrameMeta[Machine.ptr(zr_code_word(code, 1))].box != box
      zr_box_stamp(zr_ary_at(code, 4), box)
    end
    Eval.call(Machine.ptr(zr_code_word(code, 0)), RProc[b].self, RProc[b].cref, e, RProc[b].blk)
  end

  # The tree-walking interpreter's `Binding#eval`: the new locals of the
  # string, an Array of Symbols, become one new scope inside the Binding's,
  # as zr_binding_run makes the scope of a compiled string the Binding's.
  # The Binding keeps the table, so zr never frees it.
  #: (value, value) -> value
  def zr_binding_push_m(b, names)
    n = RArray[names].len
    if n == 0
      return Machine.value(QNIL)
    end
    table = zr_xmalloc((n + 1) * 8)
    Machine.store64(table, 0, n)
    i = 0
    while i < n
      Machine.store64(table + ((i + 1) * 8), 0, zr_sym2id(zr_ary_at(names, i)))
      i += 1
    end
    RProc[b].env = zr_env_new(RProc[b].env, n, table)
    Machine.value(QNIL)
  end

  # Adds a name to the Binding, in a new scope inside the Binding's scope.
  # The Binding keeps the table, so zr never frees it.
  #: (value, value) -> value
  def zr_binding_add(b, name)
    id = zr_fix2long(zr_intern_id(name))
    env = RProc[b].env
    # Later names go into the scope that the first one made, as CRuby
    # extends the binding's own env, so a lookup does not go through one
    # scope per name.
    if env != QNIL && zr_ivar_get(b, Machine.id(:__own_env__)) == env
      n = REnv[env].nslots
      table = zr_xmalloc((n + 2) * 8)
      zr_memcpy(table, REnv[env].names, (n + 1) * 8)
      Machine.store64(table, 0, n + 1)
      Machine.store64(table + ((n + 1) * 8), 0, id)
      slots = zr_xmalloc((n + 1) * 8)
      zr_memcpy(slots, REnv[env].slots, n * 8)
      Machine.store64(slots + (n * 8), 0, QNIL)
      old_names = REnv[env].names
      old_slots = REnv[env].slots
      REnv[env].names = table
      REnv[env].slots = slots
      REnv[env].nslots = n + 1
      zr_xfree(old_names)
      zr_xfree(old_slots)
      return Machine.value(QNIL)
    end
    table = zr_xmalloc(16)
    Machine.store64(table, 0, 1)
    Machine.store64(table, 8, id)
    RProc[b].env = zr_env_new(env, 1, table)
    zr_ivar_set(b, Machine.id(:__own_env__), RProc[b].env)
    Machine.value(QNIL)
  end

  # Where the local `name` is in the Binding's scopes, innermost first, as
  # [depth, index], or nil. `outer` false leaves out the outermost scope
  # (the main script's, before it runs).
  #: (value, value, value) -> value
  def zr_binding_place(b, name, outer)
    id = zr_sym2id(name)
    env = RProc[b].env
    depth = 0
    while env != QNIL
      if outer == QFALSE && REnv[env].parent == QNIL
        return Machine.value(QNIL)
      end
      t = REnv[env].names
      if t != 0
        n = Machine.load64(t, 0)
        i = 0
        while i < n
          if Machine.load64(t + 8 + (i * 8), 0) == id
            pair = zr_ary_new(2)
            zr_ary_push(pair, zr_fix(depth))
            zr_ary_push(pair, zr_fix(i))
            return pair
          end
          i += 1
        end
      end
      env = REnv[env].parent
      depth += 1
    end
    Machine.value(QNIL)
  end

  # `using` at the main file's toplevel. Ruby's rb_mod_using gives main's
  # frame a cref with the refinement, and TOPLEVEL_BINDING holds that
  # frame, so a later eval in it (ERB#result's, say) runs under entry
  # `id`.
  #: (word) -> value
  def zr_using_main(id)
    b = zr_const_get(zr_global(G_TOP_CREF), Machine.id(:TOPLEVEL_BINDING))
    return b if b == QUNDEF
    zr_hidden_set(b, zr_sym(Machine.id(:__using__)), zr_fix(id))
    Machine.value(QNIL)
  end

  # `TOPLEVEL_BINDING`: main's scope, set when the program starts.
  #: (value, value, value, ptr) -> value
  def zr_toplevel_binding(env, self_, cref, meta)
    b = zr_binding_of(meta, env, self_, cref)
    RProc[b].site = 1
    zr_const_set(zr_global(G_OBJECT), Machine.id(:TOPLEVEL_BINDING), b)
  end
end
