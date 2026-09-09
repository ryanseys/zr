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
    if zr_special_p(sup) || zr_type(sup) != T_CLASS
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("superclass must be an instance of Class (given an instance of "), 62)
      zr_buf_str(b, zr_class_name_of(sup))
      zr_buf_byte(b, 41)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
    if zr_singleton_p(sup)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't make subclass of singleton class"), 38)
    end
    if sup == zr_global(G_CLASS)
      return zr_raise_msg(zr_global(G_TYPE_ERROR), Machine.bytes("can't make subclass of Class"), 28)
    end
  end
  RClass.set_superclass(recv, sup)
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
  if argc == 0
    return zr_wrong_arity_range(0, 1, 2)
  end
  slot = Machine.slot(8)
  r = zr_name_id(Machine.value(Machine.load64(argv, 0)), slot)
  return r if r == QUNDEF
  mid = Machine.load64(slot, 0)
  body = blk
  caller = Frame.prev(Task.top(zr_task()))
  if argc > 1
    body = Machine.value(Machine.load64(argv, 8))
    if !zr_special_p(body) && zr_type(body) == T_METHOD
      e = RMethod.entry(body)
      zr_method_add_vis(recv, mid, MEntry.fn(e), MEntry.arity(e), MEntry.kind(e), MEntry.meta(e), MEntry.cref(e), zr_definition_vis(mid, Frame.cref(caller)))
      r = zr_method_added(recv, mid)
      return r if r == QUNDEF
      return zr_sym(mid)
    end
    if zr_special_p(body) || zr_type(body) != T_PROC
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
      zr_buf_str(b, zr_class_name_of(body))
      zr_buf_push(b, Machine.bytes(" (expected Proc/Method/UnboundMethod)"), 37)
      return zr_raise_buf(zr_global(G_TYPE_ERROR), b)
    end
  elsif blk == QNIL
    return zr_raise_msg(zr_global(G_ARGUMENT_ERROR), Machine.bytes("tried to create Proc object without a block"), 43)
  end
  r = zr_define_bmethod(recv, mid, zr_meta_at(caller), body, Frame.cref(caller))
  return r if r == QUNDEF
  zr_sym(mid)
end

# The call of a method made by `define_method`: the block as a lambda
# under the receiver, defining into the owner.
sig [Ptr, Value, Word, Ptr, Value] => Value
machine def zr_bmethod_call(e, recv, argc, argv, blk)
  body = MEntry.cref(e)
  p = zr_proc_under(body, recv, zr_cref_push_eval(FrameMeta.owner(MEntry.meta(e)), RProc.cref(body)))
  RProc.set_lambda(p, 1)
  RProc.set_home(p, 0)
  Machine.call(:block, RProc.fn(p), p, argc, argv, blk)
end
