# What a scope shows of itself: the frame that asked, its locals by name,
# the Env they live in, and the Binding that holds all of it.

# The frame that asked for an eval. The compiler is reached from a
# method of the runtime's own, whose frame is on top, so the frame
# outside it is the one that wrote the call.
sig [] => Ptr
machine def zr_caller_frame
  Frame.prev(Task.top(zr_task()))
end

sig [] => Value
machine def zr_eval_self
  Frame.self(zr_caller_frame())
end

sig [] => Value
machine def zr_eval_cref
  Frame.cref(zr_caller_frame())
end

# `(eval at file:line)`: the name ruby gives an eval that names no file.
sig [] => Value
machine def zr_eval_source_name
  rec = zr_frame_with_file(zr_caller_frame())
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("(eval at "), 9)
  if rec != 0
    zr_buf_push(b, FrameMeta.file(Frame.meta(rec)), FrameMeta.file_len(Frame.meta(rec)))
    zr_buf_byte(b, 58)
    zr_buf_long(b, Frame.line(rec))
  end
  zr_buf_byte(b, 41)
  zr_buf_take(b)
end

# A cref an eval on a string runs under: the module on top of the
# scope the call stands in, so a constant the enclosing module holds is
# still in reach and `Module.nesting` names them both.
sig [Value, Value] => Value
machine def zr_eval_cref_under(mod, outer)
  zr_cref_push(mod, outer)
end

# The cref a `load` with a wrap module runs its file under: the module on
# top of the toplevel's, where a def is private, as at the toplevel.
sig [Value] => Value
machine def zr_wrap_cref(mod)
  c = zr_cref_push(mod, zr_global(G_TOP_CREF))
  RCref.set_vis(c, VIS_PRIVATE)
  c
end

# The names in a locals table, as symbols in slot order.
sig [Ptr] => Value
machine def zr_local_names(table)
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

# The Env a frame keeps its locals in, or nil where it keeps them in the
# record alone. A scope that names an eval or a binding always has one,
# which is what `Scope.opens_locals?` is for.
sig [Ptr] => Value
machine def zr_frame_env(rec)
  if FrameMeta.env(Frame.meta(rec)) == 0
    return Machine.value(QNIL)
  end
  Machine.value(Machine.load64(rec + Frame.size, 0))
end

sig [] => Value
machine def zr_eval_env
  zr_frame_env(zr_caller_frame())
end

# Whether the frame that asked for an eval runs inside a method: a
# method's own body, or a block, an eval, or a block in an eval, written
# inside one.
sig [] => Value
machine def zr_eval_in_method
  zr_bool(zr_meta_in_method(Frame.meta(zr_caller_frame())))
end

sig [Value] => Value
machine def zr_binding_in_method(b)
  zr_bool(zr_meta_in_method(RProc.meta(b)))
end

sig [Ptr] => Bool
machine def zr_meta_in_method(meta)
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

# The names of every scope the asking frame can reach, innermost first:
# its own, then one array per Env out along the chain.
sig [] => Value
machine def zr_eval_scopes
  out = zr_ary_new(0)
  env = zr_eval_env()
  while env != QNIL
    zr_ary_push(out, zr_local_names(REnv.names(env)))
    env = REnv.parent(env)
  end
  out
end

# `Kernel#binding`: the scope the caller stands in, kept as a Proc of the
# Binding class. Its env, self and cref are that scope's, so a read and a
# write there are the scope's own. A Binding has no home and no call site,
# so `serial` is the line the capture stands on and `site` marks the one
# TOPLEVEL_BINDING, which ruby reports as `<main>` line 0.
sig [] => Value
machine def zr_binding
  rec = zr_caller_frame()
  b = zr_binding_of(Frame.meta(rec), zr_frame_env(rec), Frame.self(rec), Frame.cref(rec))
  RProc.set_serial(b, Frame.line(rec))
  b
end

# `Proc#binding`: the scope the block was written in, which the Proc
# already carries. The line is the block's, since a Proc holds none.
sig [Value] => Value
machine def zr_proc_binding(p)
  if RProc.meta(p) == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("Can't create Binding from C level Proc"), 38)
  end
  if (RBasic.flags(p) & FL_ISOLATED) != 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("Can't create Binding from isolated Proc"), 39)
  end
  b = zr_binding_of(RProc.meta(p), RProc.env(p), RProc.self(p), RProc.cref(p))
  RProc.set_serial(b, FrameMeta.line(RProc.meta(p)))
  b
end

sig [Ptr, Value, Value, Value] => Value
machine def zr_binding_of(meta, env, self_, cref)
  b = zr_alloc(T_PROC, zr_core_class(Machine.id(:Binding)))
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

sig [Value] => Value
machine def zr_binding_scopes(b)
  out = zr_ary_new(0)
  env = RProc.env(b)
  while env != QNIL
    zr_ary_push(out, zr_local_names(REnv.names(env)))
    env = REnv.parent(env)
  end
  out
end

sig [Value] => Value
machine def zr_binding_receiver(b)
  RProc.self(b)
end

sig [Value] => Value
machine def zr_binding_file(b)
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
machine def zr_binding_line(b)
  if RProc.site(b) != 0
    return zr_fix(0)
  end
  zr_fix(RProc.serial(b))
end

sig [Value, Value, Value] => Value
machine def zr_binding_get(b, depth, index)
  zr_env_get(zr_env_up(RProc.env(b), zr_fix2long(depth)), zr_fix2long(index))
end

sig [Value, Value, Value, Value] => Value
machine def zr_binding_set(b, depth, index, v)
  zr_env_set(zr_env_up(RProc.env(b), zr_fix2long(depth)), zr_fix2long(index), v)
  v
end

# A loaded eval toplevel run in a Binding: its self, its cref and the
# locals it holds. The Binding keeps the Env the string ran in, so a name
# the string wrote is one of the Binding's own from here on.
sig [Value, Value] => Value
machine def zr_binding_run(code, b)
  e = zr_code_env(code, RProc.env(b))
  RProc.set_env(b, e)
  zr_eval_at(code, RProc.self(b), RProc.cref(b), e)
end

# One more name the Binding holds, in a scope of its own inside the
# scope it named. The table is the Binding's, so it is never freed.
sig [Value, Value] => Value
machine def zr_binding_add(b, name)
  table = zr_xmalloc(16)
  Machine.store64(table, 0, 1)
  Machine.store64(table, 8, zr_intern(RString.ptr(name), RString.len(name)))
  RProc.set_env(b, zr_env_new(RProc.env(b), 1, table))
  Machine.value(QNIL)
end

# `TOPLEVEL_BINDING`: main's own scope, named as the program starts.
sig [Value, Value, Value, Ptr] => Value
machine def zr_toplevel_binding(env, self_, cref, meta)
  b = zr_binding_of(meta, env, self_, cref)
  RProc.set_site(b, 1)
  zr_const_set(zr_global(G_OBJECT), Machine.id(:TOPLEVEL_BINDING), b)
end
