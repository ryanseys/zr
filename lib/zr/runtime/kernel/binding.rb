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

  # `Kernel#binding`: the caller's scope, kept as a Proc of the Binding
  # class. Its env, self and cref are those of the scope, so reads and
  # writes go to the scope. A Binding has no home and no call site. Thus
  # `serial` is the line of the capture, and `site` marks the single
  # TOPLEVEL_BINDING, which ruby reports as `<main>` line 0.
  #: () -> value
  def zr_binding
    zr_binding_at(zr_caller_frame())
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

  #: (ptr) -> value
  def zr_binding_at(rec)
    blk = zr_block_proc(Frame[rec].blk)
    b = zr_binding_of(Frame[rec].meta, zr_frame_env(rec), Frame[rec].self, Frame[rec].cref)
    RProc[b].blk = blk
    RProc[b].serial = zr_frame_line(rec)
    b
  end

  # `Proc#binding`: the scope where the block was written, which the Proc
  # already contains. The line is the block's line, because a Proc has no
  # line.
  #: (value) -> value
  def zr_proc_binding(p)
    # The core's anonymous Procs (curry, Hash#to_proc) are C functions in
    # CRuby, and have no binding either.
    if RProc[p].meta == 0 || RProc[p].meta == zr_anonymous_meta()
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

  # The tree-walking interpreter (lib/zr/eval/walk/tree.rb) reads the
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
    zr_meta_file(meta)
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
    Eval.call(Machine.ptr(zr_code_word(code, 0)), RProc[b].self, RProc[b].cref, e, RProc[b].blk)
  end

  # Adds a name to the Binding, in a new scope inside the Binding's scope.
  # The Binding keeps the table, so zr never frees it.
  #: (value, value) -> value
  def zr_binding_add(b, name)
    table = zr_xmalloc(16)
    Machine.store64(table, 0, 1)
    Machine.store64(table, 8, zr_intern(RString[name].ptr, RString[name].len))
    RProc[b].env = zr_env_new(RProc[b].env, 1, table)
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
