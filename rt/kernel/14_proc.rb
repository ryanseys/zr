# Blocks. A block literal is a function taking its Proc, the arguments
# and a block of its own; the Proc carries what the body needs from
# where it was written: the captured locals (an Env), self, the cref,
# the method's own block, and two homes with their serials: the frame
# a `break` returns to (with the call site's number) and the method a
# `return` leaves. A `break` or `return` is a signal beside `raise`:
# the task's pending kind says which.
Machine.struct :REnv, basic: RBasic, parent: Value, slots: Ptr, nslots: Word
Machine.struct :RProc, basic: RBasic, fn: Ptr, env: Value, self: Value, cref: Value, blk: Value, home: Ptr, serial: Word, site: Word, ret_home: Ptr, ret_serial: Word, nparams: Word, lambda: Word
Machine.sig :block, [Value, Word, Ptr, Value] => Value
T_ENV = 26
T_PROC = 27
G_PROC = 28
G_LOCAL_JUMP_ERROR = 29
PENDING_RAISE = 0
PENDING_BREAK = 1
PENDING_RETURN = 2

sig [Value, Word] => Value
machine def zr_env_new(parent, n)
  e = zr_alloc(T_ENV, Machine.value(QNIL))
  REnv.set_parent(e, parent)
  REnv.set_nslots(e, n)
  slots = malloc(n * 8)
  i = 0
  while i < n
    Machine.store64(slots + (i * 8), 0, QNIL)
    i += 1
  end
  REnv.set_slots(e, slots)
  e
end

# The env `depth` parents up from `env`.
sig [Value, Word] => Value
machine def zr_env_up(env, depth)
  while depth > 0
    env = REnv.parent(env)
    depth -= 1
  end
  env
end

sig [Value, Word] => Value
machine def zr_env_get(env, i)
  Machine.value(Machine.load64(REnv.slots(env) + (i * 8), 0))
end

sig [Value, Word, Value] => Value
machine def zr_env_set(env, i, v)
  Machine.store64(REnv.slots(env) + (i * 8), 0, Machine.word(v))
  v
end

sig [Value] => Void
machine def zr_mark_env(e)
  zr_mark(REnv.parent(e))
  n = REnv.nslots(e)
  i = 0
  while i < n
    zr_mark(zr_env_get(e, i))
    i += 1
  end
end

sig [Value] => Void
machine def zr_mark_proc(p)
  zr_mark(RProc.env(p))
  zr_mark(RProc.self(p))
  zr_mark(RProc.cref(p))
  zr_mark(RProc.blk(p))
end

# A Proc for a block written in the frame `home` (the call site
# `site`, packed above the parameter count), whose method's frame is
# `ret_home`.
sig [Ptr, Value, Value, Value, Value, Ptr, Word, Ptr] => Value
machine def zr_proc_new(fn, env, self_, cref, blk, home, site_and_nparams, ret_home)
  site = site_and_nparams >> 32
  nparams = site_and_nparams & 4294967295
  p = zr_alloc(T_PROC, zr_global(G_PROC))
  RProc.set_fn(p, fn)
  RProc.set_env(p, env)
  RProc.set_self(p, self_)
  RProc.set_cref(p, cref)
  RProc.set_blk(p, blk)
  RProc.set_home(p, home)
  RProc.set_serial(p, Frame.serial(home))
  RProc.set_site(p, site)
  RProc.set_ret_home(p, ret_home)
  RProc.set_ret_serial(p, Frame.serial(ret_home))
  RProc.set_nparams(p, nparams)
  RProc.set_lambda(p, 0)
  p
end

# Call the block with `argc` arguments.
sig [Value, Word, Ptr] => Value
machine def zr_yield(blk, argc, argv)
  if blk == QNIL
    return zr_raise_msg(zr_global(G_LOCAL_JUMP_ERROR), Machine.bytes("no block given (yield)"), 22)
  end
  Machine.call(:block, RProc.fn(blk), blk, argc, argv, Machine.value(QNIL))
end

sig [Value, Value] => Value
machine def zr_yield1(blk, v)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(v))
  zr_yield(blk, 1, slot)
end

sig [Value, Value, Value] => Value
machine def zr_yield2(blk, a, b)
  slot = Machine.slot(16)
  Machine.store64(slot, 0, Machine.word(a))
  Machine.store64(slot, 8, Machine.word(b))
  zr_yield(blk, 2, slot)
end

# The arguments a block binds: a lone Array spreads over several
# parameters; missing ones are nil, extra ones dropped. Answers the
# argument count to read from `argv_out`.
sig [Word, Ptr, Word, Ptr] => Word
machine def zr_block_args(argc, argv, nparams, argv_out)
  if nparams > 1 && argc == 1
    v = Machine.value(Machine.load64(argv, 0))
    if !zr_special_p(v) && zr_type(v) == T_ARRAY
      Machine.store64(argv_out, 0, RArray.ptr(v))
      return RArray.len(v)
    end
  end
  Machine.store64(argv_out, 0, argv)
  argc
end

# Whether the frame `home` with `serial` is still on the stack.
sig [Ptr, Word] => Bool
machine def zr_frame_live(home, serial)
  rec = Task.top(zr_task())
  while rec != 0
    if rec == home
      return Frame.serial(rec) == serial
    end
    rec = Frame.prev(rec)
  end
  false
end

sig [Word, Value, Ptr, Word] => Value
machine def zr_signal(kind, value, home, site)
  t = zr_task()
  Task.set_pending_kind(t, kind)
  Task.set_pending(t, value)
  Task.set_pending_home(t, home)
  Task.set_pending_site(t, site)
  Machine.value(QUNDEF)
end

# `break v` in the block `p`.
sig [Value, Value] => Value
machine def zr_break(p, v)
  unless zr_frame_live(RProc.home(p), RProc.serial(p))
    return zr_raise_msg(zr_global(G_LOCAL_JUMP_ERROR), Machine.bytes("break from proc-closure"), 23)
  end
  zr_signal(PENDING_BREAK, v, RProc.home(p), RProc.site(p))
end

# `return v` in the block `p`: leaves the method the block was written in.
sig [Value, Value] => Value
machine def zr_return(p, v)
  unless zr_frame_live(RProc.ret_home(p), RProc.ret_serial(p))
    return zr_raise_msg(zr_global(G_LOCAL_JUMP_ERROR), Machine.bytes("unexpected return"), 17)
  end
  zr_signal(PENDING_RETURN, v, RProc.ret_home(p), 0)
end

# At a call site with a block: the pending break's value when it is
# this site's, else undef (the signal stays pending).
sig [Ptr, Word] => Value
machine def zr_catch_break(rec, site)
  t = zr_task()
  if Task.pending_kind(t) == PENDING_BREAK && Task.pending_home(t) == rec && Task.pending_site(t) == site
    v = Task.pending(t)
    Task.set_pending_kind(t, PENDING_RAISE)
    Task.set_pending(t, Machine.value(QNIL))
    return v
  end
  Machine.value(QUNDEF)
end

# In a method's landing block: the pending return's value when it is
# this method's, else undef.
sig [Ptr] => Value
machine def zr_catch_return(rec)
  t = zr_task()
  if Task.pending_kind(t) == PENDING_RETURN && Task.pending_home(t) == rec
    v = Task.pending(t)
    Task.set_pending_kind(t, PENDING_RAISE)
    Task.set_pending(t, Machine.value(QNIL))
    return v
  end
  Machine.value(QUNDEF)
end

# `block_given?` reads the block of the frame that called it.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_block_given_p(recv, argc, argv, cref, blk)
  caller = Frame.prev(Task.top(zr_task()))
  zr_bool(Frame.blk(caller) != QNIL)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_times(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("times without a block needs Enumerator\n"), 39)
  end
  n = zr_fix2long(recv)
  i = 0
  while i < n
    r = zr_yield1(blk, zr_fix(i))
    return r if r == QUNDEF
    i += 1
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_upto(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("upto without a block needs Enumerator\n"), 38)
  end
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  i = zr_fix2long(recv)
  last = Machine.load64(out, 0)
  while i <= last
    r = zr_yield1(blk, zr_fix(i))
    return r if r == QUNDEF
    i += 1
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_downto(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("downto without a block needs Enumerator\n"), 40)
  end
  out = Machine.slot(8)
  r = zr_int_operand(argv, out)
  return r if r == QUNDEF
  i = zr_fix2long(recv)
  last = Machine.load64(out, 0)
  while i >= last
    r = zr_yield1(blk, zr_fix(i))
    return r if r == QUNDEF
    i -= 1
  end
  recv
end

# `loop`: until a break; a StopIteration comes with Enumerator.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_loop(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("loop without a block needs Enumerator\n"), 38)
  end
  while true
    r = zr_yield(blk, 0, 0)
    return r if r == QUNDEF
  end
  Machine.value(QNIL)
end

# The Array's length is re-read every step: the block may change it.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_each(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("each without a block needs Enumerator\n"), 38)
  end
  i = 0
  while i < RArray.len(recv)
    r = zr_yield1(blk, zr_ary_at(recv, i))
    return r if r == QUNDEF
    i += 1
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_each_with_index(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("each_with_index without a block needs Enumerator\n"), 49)
  end
  i = 0
  while i < RArray.len(recv)
    r = zr_yield2(blk, zr_ary_at(recv, i), zr_fix(i))
    return r if r == QUNDEF
    i += 1
  end
  recv
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_each_index(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("each_index without a block needs Enumerator\n"), 44)
  end
  i = 0
  while i < RArray.len(recv)
    r = zr_yield1(blk, zr_fix(i))
    return r if r == QUNDEF
    i += 1
  end
  recv
end

# `map`: the answers into a new Array, which the frame keeps rooted
# through the receiver's slot.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_map(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("map without a block needs Enumerator\n"), 37)
  end
  keep = Machine.slot(8)
  out = zr_ary_new(RArray.len(recv))
  Machine.store64(keep, 0, Machine.word(out))
  zr_root_push(keep)
  i = 0
  while i < RArray.len(recv)
    r = zr_yield1(blk, zr_ary_at(recv, i))
    if r == QUNDEF
      zr_root_pop()
      return r
    end
    zr_ary_push(out, r)
    i += 1
  end
  zr_root_pop()
  out
end

# `select`/`reject`: `keep` says which answers keep the element.
sig [Value, Value, Bool] => Value
machine def zr_ary_filter(recv, blk, keep)
  slot = Machine.slot(8)
  out = zr_ary_new(4)
  Machine.store64(slot, 0, Machine.word(out))
  zr_root_push(slot)
  i = 0
  while i < RArray.len(recv)
    v = zr_ary_at(recv, i)
    r = zr_yield1(blk, v)
    if r == QUNDEF
      zr_root_pop()
      return r
    end
    if (r != QNIL && r != QFALSE) == keep
      zr_ary_push(out, zr_ary_at(recv, i))
    end
    i += 1
  end
  zr_root_pop()
  out
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_select(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("select without a block needs Enumerator\n"), 40)
  end
  zr_ary_filter(recv, blk, true)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_reject(recv, argc, argv, cref, blk)
  if blk == QNIL
    zr_bug(Machine.bytes("reject without a block needs Enumerator\n"), 40)
  end
  zr_ary_filter(recv, blk, false)
end
