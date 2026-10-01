# What a scope shows of itself: the calling frame, its locals by name,
# the Env that contains them, and the Binding that contains all of it.

module Zr::Kern
  # The frame that called eval. A runtime method calls the compiler, and
  # that method's frame is on top. Thus the next frame out is the frame
  # that contains the call.
  sig [] => Ptr
  def zr_caller_frame
    Frame.prev(Task.top(zr_task()))
  end

  # The frame that gives an eval its scope: the nearest frame written in
  # Ruby. A call through `Method#call`, `Enumerable#each` or a different
  # builtin has a frame with no locals, no cref and no block. The walk
  # skips such a frame, so `method(:eval).call("x")` reads the caller's
  # `x`. CRuby finds the same frame with rb_vm_get_ruby_level_next_cfp in
  # eval_string_with_cref, and uses all of that frame's block: its locals,
  # its ep, and its cref.
  sig [] => Ptr
  def zr_eval_frame
    zr_frame_with_file(zr_caller_frame())
  end

  sig [] => Value
  def zr_eval_cref
    Frame.cref(zr_eval_frame())
  end

  sig [] => Value
  def zr_eval_block
    Frame.blk(zr_eval_frame())
  end

  # `(eval at file:line)`: the name that ruby gives an eval with no file.
  sig [] => Value
  def zr_eval_source_name
    rec = zr_eval_frame()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("(eval at "), 9)
    if rec != 0
      zr_buf_push(b, FrameMeta.file(Frame.meta(rec)), FrameMeta.file_len(Frame.meta(rec)))
      zr_buf_byte(b, 58)
      zr_buf_long(b, zr_frame_line(rec))
    end
    zr_buf_byte(b, 41)
    zr_buf_take(b)
  end

  # The cref for an eval of a string: the module on top of the scope of
  # the call. Thus a constant of the enclosing module stays visible, and
  # `Module.nesting` shows both modules.
  sig [Value, Value] => Value
  def zr_eval_cref_under(mod, outer)
    zr_cref_push(mod, outer)
  end

  # The cref for a `load` with a wrap module: the module on top of the
  # toplevel cref. A def there is private, as at the toplevel.
  sig [Value] => Value
  def zr_wrap_cref(mod)
    c = zr_cref_push(mod, zr_global(G_TOP_CREF))
    RCref.set_vis(c, VIS_PRIVATE)
    c
  end

  # The names in a locals table, as symbols in slot order.
  sig [Ptr] => Value
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
  # has an Env; `Scope.opens_locals?` makes sure of this.
  sig [Ptr] => Value
  def zr_frame_env(rec)
    if FrameMeta.env(Frame.meta(rec)) == 0
      return Machine.value(QNIL)
    end
    zr_env_escape(Machine.value(Machine.load64(rec + Frame.size, 0)))
  end

  sig [] => Value
  def zr_eval_env
    zr_frame_env(zr_eval_frame())
  end

  # The parameters of the method that contains the frame that called eval,
  # as Method#parameters returns them. The frame can be the method body,
  # or a block, an eval, or a block in an eval inside the method. Returns
  # nil outside a method.
  sig [] => Value
  def zr_eval_parameters
    zr_meta_parameters(Frame.meta(zr_eval_frame()))
  end

  sig [Value] => Value
  def zr_binding_parameters(b)
    zr_meta_parameters(RProc.meta(b))
  end

  sig [Ptr] => Value
  def zr_meta_parameters(meta)
    if !zr_meta_in_method(meta)
      return Machine.value(QNIL)
    end
    while FrameMeta.kind(meta) != KIND_DEF
      meta = FrameMeta.parent(meta)
    end
    zr_param_rows(FrameMeta.params(meta), false)
  end

  sig [Ptr] => Bool
  def zr_meta_in_method(meta)
    while meta != 0
      kind = FrameMeta.kind(meta)
      if kind == KIND_DEF
        return true
      end
      if kind != KIND_BLOCK && kind != KIND_EVAL
        return false
      end
      meta = FrameMeta.parent(meta)
    end
    false
  end

  # The names of all scopes that the calling frame can reach, innermost
  # first: its own, then one Array for each Env along the parent list.
  sig [] => Value
  def zr_eval_scopes
    out = zr_ary_new(0)
    env = zr_eval_env()
    while env != QNIL
      zr_ary_push(out, zr_local_names(REnv.names(env)))
      env = REnv.parent(env)
    end
    out
  end

  # `Kernel#binding`: the caller's scope, kept as a Proc of the Binding
  # class. Its env, self and cref are those of the scope, so reads and
  # writes go to the scope. A Binding has no home and no call site. Thus
  # `serial` is the line of the capture, and `site` marks the single
  # TOPLEVEL_BINDING, which ruby reports as `<main>` line 0.
  sig [] => Value
  def zr_binding
    rec = zr_caller_frame()
    blk = zr_block_proc(Frame.blk(rec))
    b = zr_binding_of(Frame.meta(rec), zr_frame_env(rec), Frame.self(rec), Frame.cref(rec))
    RProc.set_blk(b, blk)
    RProc.set_serial(b, zr_frame_line(rec))
    b
  end

  # `Proc#binding`: the scope where the block was written, which the Proc
  # already contains. The line is the block's line, because a Proc has no
  # line.
  sig [Value] => Value
  def zr_proc_binding(p)
    if RProc.meta(p) == 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("Can't create Binding from C level Proc"), 38)
    end
    if (RBasic.flags(p) & FL_ISOLATED) != 0
      return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("Can't create Binding from isolated Proc"), 39)
    end
    zr_proc_scope(p)
  end

  # The scope of a Proc written in Ruby, also for an isolated Proc.
  # Ractor.shareable_proc reads a block's outer locals from it, as CRuby
  # reads its env.
  sig [Value] => Value
  def zr_proc_scope(p)
    b = zr_binding_of(RProc.meta(p), RProc.env(p), RProc.self(p), RProc.cref(p))
    RProc.set_blk(b, RProc.blk(p))
    RProc.set_serial(b, FrameMeta.line(RProc.meta(p)))
    b
  end

  sig [Ptr, Value, Value, Value] => Value
  def zr_binding_of(meta, env, self_, cref)
    b = zr_alloc(T_PROC, zr_core_class(Machine.id(:Binding)), RProc.size)
    RProc.set_fn(b, 0)
    RProc.set_meta(b, meta)
    RProc.set_env(b, env)
    RProc.set_self(b, self_)
    RProc.set_cref(b, cref)
    RProc.set_blk(b, Machine.value(QNIL))
    RProc.set_home(b, 0)
    RProc.set_serial(b, 0)
    RProc.set_site(b, 0)
    RProc.set_ret_home(b, 0)
    RProc.set_ret_serial(b, 0)
    RProc.set_spread(b, 0)
    RProc.set_lambda(b, 0)
    RProc.set_passed(b, 0)
    b
  end

  # The lexical scope of a Binding, where `binding.eval` runs its string.
  # The tree-walking interpreter reads it. The eval compiler gives the
  # Binding to `zr_binding_run` and does not read it.
  sig [Value] => Value
  def zr_binding_cref(b)
    RProc.cref(b)
  end

  sig [Value] => Value
  def zr_binding_scopes(b)
    out = zr_ary_new(0)
    env = RProc.env(b)
    while env != QNIL
      zr_ary_push(out, zr_local_names(REnv.names(env)))
      env = REnv.parent(env)
    end
    out
  end

  sig [Value] => Value
  def zr_binding_receiver(b)
    RProc.self(b)
  end

  sig [Value] => Value
  def zr_binding_file(b)
    if RProc.site(b) != 0
      return zr_str_new(Machine.bytes("<main>"), 6)
    end
    meta = RProc.meta(b)
    if FrameMeta.file_len(meta) == 0
      return Machine.value(QNIL)
    end
    zr_str_new(FrameMeta.file(meta), FrameMeta.file_len(meta))
  end

  sig [Value] => Value
  def zr_binding_line(b)
    if RProc.site(b) != 0
      return zr_fix(0)
    end
    zr_fix(RProc.serial(b))
  end

  sig [Value, Value, Value] => Value
  def zr_binding_get(b, depth, index)
    zr_env_get(zr_env_up(RProc.env(b), zr_fix2long(depth)), zr_fix2long(index))
  end

  sig [Value, Value, Value, Value] => Value
  def zr_binding_set(b, depth, index, v)
    zr_env_set(zr_env_up(RProc.env(b), zr_fix2long(depth)), zr_fix2long(index), v)
    v
  end

  # Runs a loaded eval toplevel in a Binding, with its self, its cref and
  # its locals. The Binding keeps the Env where the string ran, so a name
  # that the string wrote becomes a local of the Binding.
  sig [Value, Value] => Value
  def zr_binding_run(code, b)
    e = zr_code_env(code, RProc.env(b))
    RProc.set_env(b, e)
    # The string runs inside the Binding's scope, as CRuby makes the
    # binding's iseq its parent: `__method__` and a backtrace label read
    # the scope where the Binding was made.
    FrameMeta.set_parent(Machine.ptr(zr_code_word(code, 1)), RProc.meta(b))
    Eval.call(Machine.ptr(zr_code_word(code, 0)), RProc.self(b), RProc.cref(b), e, RProc.blk(b))
  end

  # Adds a name to the Binding, in a new scope inside the Binding's scope.
  # The Binding keeps the table, so zr never frees it.
  sig [Value, Value] => Value
  def zr_binding_add(b, name)
    table = zr_xmalloc(16)
    Machine.store64(table, 0, 1)
    Machine.store64(table, 8, zr_intern(RString.ptr(name), RString.len(name)))
    RProc.set_env(b, zr_env_new(RProc.env(b), 1, table))
    Machine.value(QNIL)
  end

  # `TOPLEVEL_BINDING`: main's scope, set when the program starts.
  sig [Value, Value, Value, Ptr] => Value
  def zr_toplevel_binding(env, self_, cref, meta)
    b = zr_binding_of(meta, env, self_, cref)
    RProc.set_site(b, 1)
    zr_const_set(zr_global(G_OBJECT), Machine.id(:TOPLEVEL_BINDING), b)
  end
end
