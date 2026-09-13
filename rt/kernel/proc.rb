# Blocks. A block literal is a function taking its Proc, the arguments
# and a block of its own; the Proc carries what the body needs from
# where it was written: the captured locals (an Env), self, the cref,
# the method's own block, and two homes with their serials: the frame
# a `break` returns to (with the call site's number) and the method a
# `return` leaves. A `break` or `return` is a signal beside `raise`:
# the task's pending kind says which.
Machine.struct :REnv, basic: RBasic, parent: Value, slots: Ptr, nslots: Word, names: Ptr
Machine.struct :RProc, basic: RBasic, fn: Ptr, meta: Ptr, env: Value, self: Value, cref: Value, blk: Value, home: Ptr, serial: Word, site: Word, ret_home: Ptr, ret_serial: Word, spread: Word, lambda: Word, passed: Word
Machine.sig :block, [Value, Word, Ptr, Value] => Value
T_ENV = 26
T_PROC = 27
# A Proc `Ractor.shareable_proc` made: frozen, calling nothing it did not
# copy, and with no Binding to reach its scope through. A copy of it is
# an ordinary Proc again, so the bit is not carried over.
FL_ISOLATED = 1 << 13
G_PROC = 28
G_LOCAL_JUMP_ERROR = 29
PENDING_RAISE = 0
PENDING_BREAK = 1
PENDING_RETURN = 2
PENDING_THROW = 3

sig [Value, Word, Ptr] => Value
machine def zr_env_new(parent, n, names)
  e = zr_alloc(T_ENV, Machine.value(QNIL))
  REnv.set_parent(e, parent)
  REnv.set_nslots(e, n)
  REnv.set_names(e, names)
  slots = zr_xmalloc(n * 8)
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
# The same block with another self, which is what a Ractor runs: the
# block's body answers to the ractor, and no frame stands between the
# call and the body where a report would show one.
sig [Value, Value] => Value
machine def zr_proc_rebind_m(p, self_)
  RProc.set_self(p, self_)
  p
end

# The locals a block reaches outside itself, as Symbols. A Ractor
# refuses a block that reaches one, and names them. A block that reaches
# none carries no table at all.
sig [Value] => Value
machine def zr_proc_captures_m(p)
  out = zr_ary_new(4)
  table = zr_proc_captures_table(p)
  if table == 0
    return out
  end
  n = Machine.load64(table, 0)
  i = 0
  while i < n
    zr_ary_push(out, zr_sym(Machine.load64(table + 8 + (i * 16), 0)))
    i += 1
  end
  out
end

# The same locals as `[name, written, rebound]` rows: whether the block
# writes the local, and whether the scope that owns it binds it more
# than once. `Ractor.shareable_proc` refuses a block for either.
sig [Value] => Value
machine def zr_proc_capture_rows_m(p)
  out = zr_ary_new(4)
  table = zr_proc_captures_table(p)
  if table == 0
    return out
  end
  n = Machine.load64(table, 0)
  i = 0
  while i < n
    row = table + 8 + (i * 16)
    flags = Machine.load64(row, 8)
    triple = zr_ary_new(3)
    zr_ary_push(triple, zr_sym(Machine.load64(row, 0)))
    zr_ary_push(triple, zr_bool((flags & 1) != 0))
    zr_ary_push(triple, zr_bool((flags & 2) != 0))
    zr_ary_push(out, triple)
    i += 1
  end
  out
end

# A copy of `p` any ractor may call, answering to `self_`. A literal
# block becomes a lambda when `lambda` asks; a Proc that was passed in
# keeps what it is, as ruby's `shareable_lambda(&pr)` does.
sig [Value, Value, Value] => Value
machine def zr_proc_isolated_m(p, self_, lambda)
  copy = zr_copy_cell(p)
  if copy == QUNDEF
    return copy
  end
  RProc.set_self(copy, self_)
  if lambda == QTRUE && RProc.passed(p) == 0
    RProc.set_lambda(copy, 1)
  end
  RBasic.set_flags(copy, RBasic.flags(copy) | FL_FREEZE | FL_ISOLATED)
  copy
end

# A native Proc has no meta, and no locals to reach.
sig [Value] => Ptr
machine def zr_proc_captures_table(p)
  meta = RProc.meta(p)
  if meta == 0
    return 0
  end
  FrameMeta.captures(meta)
end

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
  RProc.set_passed(p, 0)
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
  RProc.set_passed(p, 1)
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

# `#<Proc:0x... file:line (lambda)>`; a Symbol's Proc shows `(&:sym)`
# and a core-made or Method Proc no location.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_inspect(recv, argc, argv, cref, blk)
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_obj_head(b, recv)
  meta = RProc.meta(recv)
  if RProc.fn(recv) == Machine.addr(:zr_symbol_block)
    zr_buf_push(b, Machine.bytes("(&"), 2)
    s = zr_inspect(RProc.self(recv))
    if s == QUNDEF
      free(Buf.ptr(b))
      return s
    end
    zr_buf_str(b, s)
    zr_buf_byte(b, 41)
  elsif meta != 0 && FrameMeta.file(meta) != 0
    zr_buf_byte(b, 32)
    zr_buf_push(b, FrameMeta.file(meta), FrameMeta.file_len(meta))
    zr_buf_byte(b, 58)
    zr_buf_long(b, FrameMeta.line(meta))
  end
  if RProc.lambda(recv) != 0
    zr_buf_push(b, Machine.bytes(" (lambda)"), 9)
  end
  zr_buf_byte(b, 62)
  zr_buf_take(b)
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

# `Proc.new { }`: as `proc`, and the arguments go to `initialize`, which
# takes none, as rb_proc_s_new passes them.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_s_new(recv, argc, argv, cref, blk)
  p = zr_kernel_proc(recv, 0, argv, cref, blk)
  return p if p == QUNDEF
  if argc != 0
    return zr_wrong_arity(argc, 0)
  end
  p
end

# `lambda { }`: the block's Proc, strict about its arguments and with
# `return` leaving the lambda itself. A Proc passed with `&` has to be a
# lambda already -- a `->`, a Method's, a Symbol's -- and comes back as
# it is; any other one is refused.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_kernel_lambda(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("tried to create Proc object without a block"), 43)
  end
  if RProc.passed(blk) != 0
    if RProc.lambda(blk) != 0
      return blk
    end
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("the lambda method requires a literal block"), 42)
  end
  RProc.set_lambda(blk, 1)
  blk
end

# `&value` at a call: nil passes no block, a Proc itself (marked as
# passed: no longer a literal block, which `lambda` refuses), a Symbol
# its Proc; anything else must answer `to_proc`.
sig [Value] => Value
machine def zr_block_pass(v)
  if v == QNIL || zr_symbol_p(v)
    if zr_symbol_p(v)
      return zr_sym_to_proc(v)
    end
    return v
  end
  if !zr_special_p(v) && zr_type(v) == T_PROC
    RProc.set_passed(v, 1)
    return v
  end
  if zr_find_method(zr_class_of(v), Machine.id(:to_proc)) == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    zr_buf_class_of(b, v)
    zr_buf_push(b, Machine.bytes(" into Proc"), 10)
    return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
  end
  pr = zr_send(v, Machine.id(:to_proc), 0, 0)
  if pr == QUNDEF || (!zr_special_p(pr) && zr_type(pr) == T_PROC)
    return pr
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("can't convert "), 14)
  zr_buf_class_of(b, v)
  zr_buf_push(b, Machine.bytes(" to Proc ("), 10)
  zr_buf_class_of(b, v)
  zr_buf_push(b, Machine.bytes("#to_proc gives "), 15)
  zr_buf_class_of(b, pr)
  zr_buf_push(b, Machine.bytes(")"), 1)
  zr_raise_buf(zr_global(G_TYPE_ERROR), b)
end

# Call the block with `argc` arguments.
sig [Value, Word, Ptr] => Value
machine def zr_yield(blk, argc, argv)
  if blk == QNIL
    return zr_local_jump_error(Machine.bytes("no block given (yield)"), 22, Machine.id(:noreason), Machine.value(QNIL))
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

# The arguments a block binds: a lone Array, or a value whose `to_ary`
# answers one, spreads over the parameters when the block's shape asks
# for it; missing ones are nil, extra ones dropped. Answers the
# argument count (a fixnum) to read from `argv_out`, or QUNDEF when
# `to_ary` raised.
sig [Word, Ptr, Word, Ptr] => Value
machine def zr_block_args(argc, argv, spread, argv_out)
  if spread != 0 && argc == 1
    v = Machine.value(Machine.load64(argv, 0))
    if !zr_special_p(v) && zr_type(v) == T_ARRAY
      Machine.store64(argv_out, 0, RArray.ptr(v))
      return zr_fix(RArray.len(v))
    end
    if !zr_special_p(v) && zr_find_method(zr_class_of(v), Machine.id(:to_ary)) != 0
      a = zr_send(v, Machine.id(:to_ary), 0, 0)
      return a if a == QUNDEF
      if !zr_special_p(a) && zr_type(a) == T_ARRAY
        Machine.store64(argv_out, 0, RArray.ptr(a))
        return zr_fix(RArray.len(a))
      end
      if a != QNIL
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("can't convert "), 14)
        zr_buf_class_of(b, v)
        zr_buf_push(b, Machine.bytes(" to Array ("), 11)
        zr_buf_class_of(b, v)
        zr_buf_push(b, Machine.bytes("#to_ary gives "), 14)
        zr_buf_class_of(b, a)
        zr_buf_push(b, Machine.bytes(")"), 1)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
    end
  end
  Machine.store64(argv_out, 0, argv)
  zr_fix(argc)
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

# A LocalJumpError with its reason (`:break`, `:return`, `:noreason`)
# and the value the jump carried.
sig [Ptr, Word, Word, Value] => Value
machine def zr_local_jump_error(bytes, len, reason, v)
  exc = zr_exc_new(zr_global(G_LOCAL_JUMP_ERROR), zr_str_new(bytes, len))
  zr_ivar_set(exc, Machine.id(:@exit_value), v)
  zr_ivar_set(exc, Machine.id(:@reason), zr_sym(reason))
  zr_raise(exc)
end

# `break v` in the block `p`.
sig [Value, Value] => Value
machine def zr_break(p, v)
  unless (RBasic.flags(p) & FL_ISOLATED) == 0 && zr_frame_live(RProc.home(p), RProc.serial(p)) && zr_block_call_live(p)
    return zr_local_jump_error(Machine.bytes("break from proc-closure"), 23, Machine.id(:break), v)
  end
  zr_signal(PENDING_BREAK, v, RProc.home(p), RProc.site(p))
end

# Whether the call `p` was given to is still running. A break leaves that
# call, so once it has returned there is nothing to break out of, though
# the method the block was written in may still be running: the block
# was kept, and called later.
#
# The frame `home` is running a call now is the one whose `prev` is
# `home` -- a frame makes one call at a time -- and that call is the one
# the block was given to when its block is this block: this Proc, or one
# made from the same literal in the same run of `home`, as `instance_exec`
# makes to run the block under another self.
sig [Value] => Bool
machine def zr_block_call_live(p)
  home = RProc.home(p)
  rec = Task.top(zr_task())
  while rec != 0 && rec != home
    if Frame.prev(rec) == home
      return zr_same_block(Frame.blk(rec), p)
    end
    rec = Frame.prev(rec)
  end
  false
end

sig [Value, Value] => Bool
machine def zr_same_block(given, p)
  if given == p
    return true
  end
  if zr_special_p(given) || zr_type(given) != T_PROC
    return false
  end
  RProc.fn(given) == RProc.fn(p) && RProc.home(given) == RProc.home(p) && RProc.serial(given) == RProc.serial(p) && RProc.site(given) == RProc.site(p)
end

# `return v` in the block `p`: leaves the method the block was written in.
sig [Value, Value] => Value
machine def zr_return(p, v)
  # A shareable Proc is cut off from the method it was written in, so
  # there is no method for its `return` to leave.
  unless (RBasic.flags(p) & FL_ISOLATED) == 0 && zr_frame_live(RProc.ret_home(p), RProc.ret_serial(p))
    return zr_local_jump_error(Machine.bytes("unexpected return"), 17, Machine.id(:return), v)
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

# `return` written in an eval carries no home: the signal belongs to
# the nearest method that armed the catch, which is the method the
# eval sits in.
sig [Value] => Value
machine def zr_return_here(v)
  zr_signal(PENDING_RETURN, v, 0, 0)
end

# In the landing block of a method that holds an eval: the pending
# return's value when it carries no home of its own, else undef.
sig [] => Value
machine def zr_catch_return_here
  t = zr_task()
  if Task.pending_kind(t) == PENDING_RETURN && Task.pending_home(t) == 0
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
  if !zr_fixnum_p(recv)
    return zr_big_route_blk(recv, Machine.id(:times), argc, argv, blk)
  end
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

# The bound of `upto` (dir 1) or `downto` (dir -1) into `out`: a
# fixnum as it is, a Float as its floor or ceiling; anything else
# coerces or fails as an Integer operand does.
sig [Value, Ptr, Ptr, Word] => Value
machine def zr_int_bound(recv, argv, out, dir)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_float_p(other)
    d = zr_float_value(other)
    if zr_nan_p(d)
      # Nothing compares with NaN: an empty walk.
      Machine.store64(out, 0, zr_fix2long(recv) - dir)
      return Machine.value(QNIL)
    end
    d = dir > 0 ? Machine.floor(d) : Machine.ceil(d)
    if d > Machine.f64(4890909195324358656)
      d = Machine.f64(4890909195324358656)
    elsif d < Machine.f64(0) - Machine.f64(4890909195324358656)
      d = Machine.f64(0) - Machine.f64(4890909195324358656)
    end
    Machine.store64(out, 0, Machine.to_int(d))
    return Machine.value(QNIL)
  end
  if zr_big_p(other)
    # A Bignum bound lies past every fixnum: the walk runs to the end of
    # the fixnum range, or not at all.
    beyond = zr_send(other, Machine.id(:negative?), 0, 0)
    return beyond if beyond == QUNDEF
    toward = beyond == QTRUE ? 0 - 1 : 1
    if toward == dir
      Machine.store64(out, 0, dir > 0 ? 4611686018427387903 : 0 - 4611686018427387904)
    else
      Machine.store64(out, 0, zr_fix2long(recv) - dir)
    end
    return Machine.value(QNIL)
  end
  if !zr_fixnum_p(other)
    return zr_cmperr(recv, other)
  end
  zr_int_operand(recv, argv, out, 0, 3)
end

# The size of `upto` or `downto`: the steps to the bound, exactly for a
# Bignum, 0 on the wrong side; nil for a bound that is no number.
sig [Value, Word, Ptr, Word] => Value
machine def zr_int_step_size(recv, argc, argv, dir)
  if argc != 1
    return Machine.value(QNIL)
  end
  other = Machine.value(Machine.load64(argv, 0))
  if zr_big_p(other)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(dir > 0 ? recv : other))
    span = zr_send(dir > 0 ? other : recv, Machine.id(:-), 1, slot)
    return span if span == QUNDEF
    if zr_send(span, Machine.id(:negative?), 0, 0) == QTRUE
      return zr_fix(0)
    end
    Machine.store64(slot, 0, Machine.word(zr_fix(1)))
    return zr_send(span, Machine.id(:+), 1, slot)
  end
  if !zr_fixnum_p(other) && !zr_float_p(other)
    return Machine.value(QNIL)
  end
  out = Machine.slot(8)
  r = zr_int_bound(recv, argv, out, dir)
  return r if r == QUNDEF
  n = ((Machine.load64(out, 0) - zr_fix2long(recv)) * dir) + 1
  zr_fix(n < 0 ? 0 : n)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_int_upto(recv, argc, argv, cref, blk)
  if !zr_fixnum_p(recv)
    return zr_big_route_blk(recv, Machine.id(:upto), argc, argv, blk)
  end
  if blk == QNIL
    return zr_enum_for(recv, Machine.id(:upto), argc, argv, zr_int_step_size(recv, argc, argv, 1))
  end
  out = Machine.slot(8)
  r = zr_int_bound(recv, argv, out, 1)
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
  if !zr_fixnum_p(recv)
    return zr_big_route_blk(recv, Machine.id(:downto), argc, argv, blk)
  end
  if blk == QNIL
    return zr_enum_for(recv, Machine.id(:downto), argc, argv, zr_int_step_size(recv, argc, argv, 0 - 1))
  end
  out = Machine.slot(8)
  r = zr_int_bound(recv, argv, out, 0 - 1)
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

# A builtin iterator called with no block: `to_enum(:name, *args)`,
# with the count of what it would yield, or nil when that is unknown.
sig [Value, Word, Word, Ptr, Value] => Value
machine def zr_enum_for(recv, mid, argc, argv, size)
  # A builtin called by an alias -- `filter` for `select`, `each_pair`
  # for `each` -- answers an enumerator that names the alias, as ruby's
  # records the called name.
  top = Task.top(zr_task())
  if Frame.mid(top) != 0 && Frame.meta(top) != 0 && FrameMeta.kind(Frame.meta(top)) == KIND_BUILTIN
    mid = Frame.mid(top)
  end
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

# Whether `v` is an Array whose `each` is Array's own, so a method of
# Enumerable may walk it by index and answer as `each` would.
sig [Value] => Value
machine def zr_ary_plain_each_p(v)
  if zr_special_p(v) || zr_type(v) != T_ARRAY
    return Machine.value(QFALSE)
  end
  zr_key_builtin_p(v, Machine.id(:each), Machine.addr(:zr_ary_each)) ? Machine.value(QTRUE) : Machine.value(QFALSE)
end

sig [Value, Value] => Value
machine def zr_ary_each_with_index_m(recv, blk)
  zr_ary_each_with_index(recv, 0, 0, Machine.value(QNIL), blk)
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

# `collect`: map's body, and an Enumerator that names `collect`, as
# CRuby's does for the name it was called by.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_ary_collect(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_enum_for(recv, Machine.id(:collect), argc, argv, zr_fix(RArray.len(recv)))
  end
  zr_ary_map(recv, argc, argv, cref, blk)
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

# A proc made by a core method, as `curry` and `>>` make: its
# parameters read `[[:rest]]` and its arity -1, whatever the block
# behind it takes, as CRuby's C-made procs do.
sig [] => Ptr
machine def zr_anonymous_meta
  meta = Machine.static(:anonymous_meta, FrameMeta.size)
  if FrameMeta.params(meta) == 0
    table = zr_xmalloc(24)
    Machine.store64(table, 0, 1)
    Machine.store64(table, 8, PARAM_REST)
    Machine.store64(table, 16, 0)
    FrameMeta.set_params(meta, table)
    FrameMeta.set_arity(meta, 0 - 1)
    FrameMeta.set_kind(meta, KIND_BLOCK)
    FrameMeta.set_owner(meta, Machine.value(QNIL))
  end
  meta
end

sig [Value] => Value
machine def zr_proc_anonymous(p)
  RProc.set_meta(p, zr_anonymous_meta())
  p
end

# Two Procs are the same when they wrap one block over one scope, as
# `dup` and `clone` make them.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_eq(recv, argc, argv, cref, blk)
  other = Machine.value(Machine.load64(argv, 0))
  if zr_special_p(other) || zr_type(other) != T_PROC
    return Machine.value(QFALSE)
  end
  zr_bool(RProc.fn(recv) == RProc.fn(other) && RProc.env(recv) == RProc.env(other) &&
          RProc.self(recv) == RProc.self(other) && RProc.lambda(recv) == RProc.lambda(other))
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_proc_hash(recv, argc, argv, cref, blk)
  zr_fix(zr_hash_mix(Machine.word(RProc.fn(recv)) ^ Machine.word(RProc.env(recv))) & 4611686018427387903)
end
