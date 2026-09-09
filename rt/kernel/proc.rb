# Blocks. A block literal is a function taking its Proc, the arguments
# and a block of its own; the Proc carries what the body needs from
# where it was written: the captured locals (an Env), self, the cref,
# the method's own block, and two homes with their serials: the frame
# a `break` returns to (with the call site's number) and the method a
# `return` leaves. A `break` or `return` is a signal beside `raise`:
# the task's pending kind says which.
Machine.struct :REnv, basic: RBasic, parent: Value, slots: Ptr, nslots: Word
Machine.struct :RProc, basic: RBasic, fn: Ptr, meta: Ptr, env: Value, self: Value, cref: Value, blk: Value, home: Ptr, serial: Word, site: Word, ret_home: Ptr, ret_serial: Word, spread: Word, lambda: Word
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
# `site`, packed above the spread flag: whether a lone Array argument
# spreads over the parameters), whose method's frame is `ret_home`.
sig [Ptr, Value, Value, Value, Value, Ptr, Word, Ptr] => Value
machine def zr_proc_new(meta, env, self_, cref, blk, home, site_and_spread, ret_home)
  site = site_and_spread >> 32
  spread = site_and_spread & 4294967295
  p = zr_alloc(T_PROC, zr_global(G_PROC))
  RProc.set_fn(p, FrameMeta.fn(meta))
  RProc.set_meta(p, meta)
  RProc.set_env(p, env)
  RProc.set_self(p, self_)
  RProc.set_cref(p, cref)
  RProc.set_blk(p, blk)
  RProc.set_home(p, home)
  RProc.set_serial(p, Frame.serial(home))
  RProc.set_site(p, site)
  RProc.set_ret_home(p, ret_home)
  RProc.set_ret_serial(p, Frame.serial(ret_home))
  RProc.set_spread(p, spread)
  RProc.set_lambda(p, 0)
  p
end

# `&:name`: a Proc sending `name` to its first argument. The block
# function reads the Symbol from the Proc's self.
sig [Value, Word, Ptr, Value] => Value
machine def zr_symbol_block(p, argc, argv, blk)
  if argc == 0
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("no receiver given"), 17)
  end
  zr_send_blk(Machine.value(Machine.load64(argv, 0)), zr_sym2id(RProc.self(p)), argc - 1, argv + 8, blk)
end

sig [Value] => Value
machine def zr_sym_to_proc(sym)
  zr_native_proc(Machine.addr(:zr_symbol_block), sym)
end

# A lambda whose body is the kernel function `fn`, with `self_` as
# what it works on: a Symbol's or a Method's Proc.
sig [Ptr, Value] => Value
machine def zr_native_proc(fn, self_)
  p = zr_alloc(T_PROC, zr_global(G_PROC))
  RProc.set_fn(p, fn)
  RProc.set_meta(p, 0)
  RProc.set_env(p, Machine.value(QNIL))
  RProc.set_self(p, self_)
  RProc.set_cref(p, Machine.value(QNIL))
  RProc.set_blk(p, Machine.value(QNIL))
  RProc.set_home(p, 0)
  RProc.set_serial(p, 0)
  RProc.set_site(p, 0)
  RProc.set_ret_home(p, 0)
  RProc.set_ret_serial(p, 0)
  RProc.set_spread(p, 0)
  RProc.set_lambda(p, 1)
  p
end

sig [Value] => Value
machine def zr_proc_lambda(p)
  RProc.set_lambda(p, 1)
  RProc.set_home(p, 0)
  p
end

# `Proc#call`: the block with the arguments, and a block of its own.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_call(recv, argc, argv, cref, blk)
  Machine.call(:block, RProc.fn(recv), recv, argc, argv, blk)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_lambda_p(recv, argc, argv, cref, blk)
  zr_bool(RProc.lambda(recv) != 0)
end

# `proc { }` and `Proc.new { }`: the block's Proc, with no call site
# for a `break` to reach any more.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_proc(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("tried to create Proc object without a block"), 43)
  end
  RProc.set_home(blk, 0)
  blk
end

# `lambda { }`: the block's Proc, strict about its arguments and with
# `return` leaving the lambda itself.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_lambda(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("tried to create Proc object without a block"), 43)
  end
  RProc.set_lambda(blk, 1)
  blk
end

# `&value` at a call: nil passes no block, a Proc itself, a Symbol its
# Proc; anything else must answer `to_proc`.
sig [Value] => Value
machine def zr_block_pass(v)
  if v == QNIL || zr_symbol_p(v)
    if zr_symbol_p(v)
      return zr_sym_to_proc(v)
    end
    return v
  end
  if !zr_special_p(v) && zr_type(v) == T_PROC
    return v
  end
  if zr_find_method(zr_class_of(v), Machine.id(:to_proc)) == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    zr_buf_str(b, zr_class_name_of(v))
    zr_buf_push(b, Machine.bytes(" into Proc"), 10)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  zr_send(v, Machine.id(:to_proc), 0, 0)
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

# The arguments a block binds: a lone Array spreads over the parameters
# when the block's shape asks for it; missing ones are nil, extra ones
# dropped. Answers the argument count to read from `argv_out`.
sig [Word, Ptr, Word, Ptr] => Word
machine def zr_block_args(argc, argv, spread, argv_out)
  if spread != 0 && argc == 1
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
    return zr_enum_for(recv, Machine.id(:times), argc, argv, recv)
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
    return zr_enum_for(recv, Machine.id(:upto), argc, argv, Machine.value(QNIL))
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
    return zr_enum_for(recv, Machine.id(:downto), argc, argv, Machine.value(QNIL))
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
    return zr_enum_for(recv, Machine.id(:loop), argc, argv, Machine.value(QNIL))
  end
  while true
    r = zr_yield(blk, 0, 0)
    return r if r == QUNDEF
  end
  Machine.value(QNIL)
end

# A builtin iterator called with no block: `to_enum(:name, *args)`,
# with the count of what it would yield, or nil when that is unknown.
sig [Value, Word, Word, Ptr, Value] => Value
machine def zr_enum_for(recv, mid, argc, argv, size)
  args = zr_ary_new(argc + 2)
  zr_ary_push(args, zr_sym(mid))
  i = 0
  while i < argc
    zr_ary_push(args, Machine.value(Machine.load64(argv + (i * 8), 0)))
    i += 1
  end
  zr_ary_push(args, size)
  zr_send(recv, Machine.id(:enum_with_size), RArray.len(args), RArray.ptr(args))
end

# The Array's length is re-read every step: the block may change it.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_each(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_enum_for(recv, Machine.id(:each), argc, argv, zr_fix(RArray.len(recv)))
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
    return zr_enum_for(recv, Machine.id(:each_with_index), argc, argv, zr_fix(RArray.len(recv)))
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
    return zr_enum_for(recv, Machine.id(:each_index), argc, argv, zr_fix(RArray.len(recv)))
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
    return zr_enum_for(recv, Machine.id(:map), argc, argv, zr_fix(RArray.len(recv)))
  end
  out = zr_ary_new(RArray.len(recv))
  i = 0
  while i < RArray.len(recv)
    r = zr_yield1(blk, zr_ary_at(recv, i))
    return r if r == QUNDEF
    zr_ary_push(out, r)
    i += 1
  end
  out
end

# `select`/`reject`: `keep` says which answers keep the element.
sig [Value, Value, Bool] => Value
machine def zr_ary_filter(recv, blk, keep)
  out = zr_ary_new(4)
  i = 0
  while i < RArray.len(recv)
    v = zr_ary_at(recv, i)
    r = zr_yield1(blk, v)
    return r if r == QUNDEF
    if (r != QNIL && r != QFALSE) == keep
      zr_ary_push(out, zr_ary_at(recv, i))
    end
    i += 1
  end
  out
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_select(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_enum_for(recv, Machine.id(:select), argc, argv, zr_fix(RArray.len(recv)))
  end
  zr_ary_filter(recv, blk, true)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_reject(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_enum_for(recv, Machine.id(:reject), argc, argv, zr_fix(RArray.len(recv)))
  end
  zr_ary_filter(recv, blk, false)
end

# What a block passed on to `each` sees as the element: the one value
# yielded, or the several as an Array.
sig [Value] => Value
machine def zr_enum_value(values)
  if RArray.len(values) == 1
    return zr_ary_at(values, 0)
  end
  if RArray.len(values) == 0
    return Machine.value(QNIL)
  end
  values
end
