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

# A cref an eval on a string runs under: the module alone, which is a
# lexical scope of its own, so `Module.nesting` there is `[mod]`.
sig [Value] => Value
machine def zr_eval_cref_of(mod)
  zr_cref_push(mod, zr_global(G_TOP_CREF))
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
# write there are the scope's own; `serial`, which a Binding has no home
# for, is the line the capture stands on.
sig [] => Value
machine def zr_binding
  rec = zr_caller_frame()
  b = zr_alloc(T_PROC, zr_core_class(Machine.id(:Binding)))
  RProc.set_fn(b, 0)
  RProc.set_meta(b, Frame.meta(rec))
  RProc.set_env(b, zr_frame_env(rec))
  RProc.set_self(b, Frame.self(rec))
  RProc.set_cref(b, Frame.cref(rec))
  RProc.set_blk(b, Machine.value(QNIL))
  RProc.set_home(b, 0)
  RProc.set_serial(b, Frame.line(rec))
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
  meta = RProc.meta(b)
  if FrameMeta.file_len(meta) == 0
    return Machine.value(QNIL)
  end
  zr_str_new(FrameMeta.file(meta), FrameMeta.file_len(meta))
end

sig [Value] => Value
machine def zr_binding_line(b)
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
# locals it holds.
sig [Value, Value] => Value
machine def zr_binding_run(code, b)
  zr_eval_run(code, RProc.self(b), RProc.cref(b), RProc.env(b))
end
