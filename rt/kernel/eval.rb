# Running a block under another self: `instance_eval`, `class_eval`,
# `Class.new { }`, and the methods `define_method` makes of a block.
#
# The block's Proc is copied with the new self and a cref pushed for
# the eval, which is where a `def` in the block lands; constants and
# class variables look through it (see RCref).

# A method whose body is a block: the entry's `cref` slot holds the
# Proc, and a call runs it under the receiver as a lambda.
KIND_BMETHOD = 8

sig [Value, Value, Value] => Value
machine def zr_proc_under(p, self_, cref)
  copy = zr_alloc(T_PROC, zr_global(G_PROC))
  zr_memcpy(Machine.ptr(copy) + RBasic.size, Machine.ptr(p) + RBasic.size, RProc.size - RBasic.size)
  RProc.set_self(copy, self_)
  RProc.set_cref(copy, cref)
  copy
end

# The block run with `self_` as self and `klass` as the definee.
sig [Value, Value, Value, Word, Ptr] => Value
machine def zr_yield_under(blk, self_, klass, argc, argv)
  p = zr_proc_under(blk, self_, zr_cref_push_eval(klass, RProc.cref(blk)))
  Machine.call(:block, RProc.fn(p), p, argc, argv, Machine.value(QNIL))
end

sig [] => Value
machine def zr_no_block_given
  zr_raise_msg(zr_global(G_LOCAL_JUMP_ERROR), Machine.bytes("no block given (yield)"), 22)
end

# `Class#initialize(superclass) { }`, under a class `Class#new` made
# with no superclass yet: the chain, the `inherited` hook, then the
# block under the class, given the class.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_class_initialize(recv, argc, argv, cref, blk)
  if RClass.superclass(recv) != QNIL || RBasic.klass(recv) != zr_global(G_CLASS)
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
  end
  RClass.set_superclass(recv, sup)
  zr_methods_changed()
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

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_module_initialize(recv, argc, argv, cref, blk)
  if blk != QNIL
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(recv))
    r = zr_yield_under(blk, recv, recv, 1, slot)
    return r if r == QUNDEF
  end
  recv
end

# `class_eval { }` and `module_eval { }`: the block under the module,
# given it; `class_exec` passes the arguments instead.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_class_eval(recv, argc, argv, cref, blk)
  if blk == QNIL
    if argc > 0
      zr_bug(Machine.bytes("class_eval with a string is not implemented yet\n"), 48)
    end
    return zr_no_block_given()
  end
  if argc != 0
    return zr_wrong_arity(argc, 0)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(recv))
  zr_yield_under(blk, recv, recv, 1, slot)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_class_exec(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_no_block_given()
  end
  zr_yield_under(blk, recv, recv, argc, argv)
end

# Where a `def` inside `instance_eval` lands: the object's singleton
# class, or the class of a special constant.
sig [Value] => Value
machine def zr_eval_class_of(obj)
  if zr_special_p(obj)
    return zr_class_of(obj)
  end
  zr_singleton_class(obj)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_instance_eval(recv, argc, argv, cref, blk)
  if blk == QNIL
    if argc > 0
      zr_bug(Machine.bytes("instance_eval with a string is not implemented yet\n"), 51)
    end
    return zr_no_block_given()
  end
  if argc != 0
    return zr_wrong_arity(argc, 0)
  end
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(recv))
  zr_yield_under(blk, recv, zr_eval_class_of(recv), 1, slot)
end

sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_instance_exec(recv, argc, argv, cref, blk)
  if blk == QNIL
    return zr_no_block_given()
  end
  zr_yield_under(blk, recv, zr_eval_class_of(recv), argc, argv)
end

# `define_method(name) { }`, or with a Proc, Method or UnboundMethod
# in place of the block: a method the block's body answers.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_mod_define_method(recv, argc, argv, cref, blk)
  if zr_frozen_p(zr_origin(recv))
    return zr_frozen_error(recv)
  end
  if argc == 0
    return zr_wrong_arity_range(0, 1, 2)
  end
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  mid = Machine.load64(slot, 0)
  body = blk
  caller = Frame.prev(Task.top(zr_task()))
  cref = zr_cref_in_context(caller, recv)
  if argc > 1
    body = Machine.value(Machine.load64(argv, 8))
    if !zr_special_p(body) && zr_type(body) == T_METHOD
      e = RMethod.entry(body)
      owner = FrameMeta.owner(MEntry.meta(e))
      if MEntry.meta(e) != 0 && owner != recv && zr_type(owner) != T_MODULE && !zr_class_inherits(recv, owner)
        if zr_singleton_p(owner)
          return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't bind singleton method to a different class"), 47)
        end
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("bind argument must be a subclass of "), 36)
        zr_buf_class(b, owner)
        return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
      end
      # A bare `module_function` is a mode: the copy takes both halves,
      # as a `def` under it does.
      modfn = cref != QNIL && RCref.modfn(cref) != 0
      if modfn
        zr_method_copy(zr_singleton_class(recv), mid, e, zr_meta_owned_by(MEntry.meta(e), recv), VIS_PUBLIC, false)
      end
      zr_method_copy(recv, mid, e, zr_meta_owned_by(MEntry.meta(e), recv), zr_definition_vis(mid, cref), false)
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
  r = zr_define_bmethod(recv, mid, zr_meta_at(caller), body, cref)
  return r if r == QUNDEF
  zr_sym(mid)
end

# A copy of `meta` with `owner` as its owner and the name it had: what
# a method copied by `define_method(name, method)` shows in a
# backtrace, as CRuby labels it.
sig [Ptr, Value] => Ptr
machine def zr_meta_owned_by(meta, owner)
  if meta == 0
    return 0
  end
  copy = malloc(FrameMeta.size)
  zr_memcpy(copy, meta, FrameMeta.size)
  FrameMeta.set_owner(copy, zr_origin(owner))
  copy
end

# The cref whose visibility a `define_method` into `mod` takes: the
# calling frame's, only when that frame is `mod`'s own body; from
# anywhere else the method is public.
sig [Ptr, Value] => Value
machine def zr_cref_in_context(frame, mod)
  cref = Frame.cref(frame)
  if Frame.self(frame) != mod || cref == QNIL || RCref.klass(cref) != mod
    return Machine.value(QNIL)
  end
  cref
end

# `define_singleton_method(name) { }`: the same, on the singleton class.
sig [Value, Word, Ptr, Value, Value] => Value
machine def zr_obj_define_singleton_method(recv, argc, argv, cref, blk)
  if zr_special_p(recv) && recv != QNIL && recv != QTRUE && recv != QFALSE
    return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't define singleton"), 22)
  end
  zr_mod_define_method(zr_singleton_class(recv), argc, argv, cref, blk)
end

# The call of a method made by `define_method`: the block as a lambda
# under the receiver, defining into the owner.
sig [Ptr, Value, Word, Ptr, Value] => Value
machine def zr_bmethod_call(e, recv, argc, argv, blk)
  body = MEntry.cref(e)
  if RProc.meta(body) == 0
    # a Symbol's or Method's Proc works on its arguments alone
    return Machine.call(:block, RProc.fn(body), body, argc, argv, blk)
  end
  cref = zr_cref_push_eval(FrameMeta.owner(MEntry.meta(e)), RProc.cref(body))
  RCref.set_entry(cref, e)
  p = zr_proc_under(body, recv, cref)
  RProc.set_lambda(p, 1)
  RProc.set_home(p, 0)
  Machine.call(:block, RProc.fn(p), p, argc, argv, blk)
end

# The body of a `refine` block, under the holder module: a `def` in it
# lands there, and the block is given the holder.
sig [Value, Value] => Value
machine def zr_refine_body(blk, holder)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(holder))
  zr_yield_under(blk, holder, holder, 1, slot)
end
