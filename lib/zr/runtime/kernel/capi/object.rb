module Zr::Kern
  # The C API's objects: freezing, kinds, instance variables, constants,
  # conversions and type errors.

  # rb_obj_freeze: freezes `obj` (not through a `freeze` that a class
  # defines), and returns it.
  #: (value) -> value
  def rb_obj_freeze(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_obj_freeze(obj, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL))
  end

  #: (value) -> value
  def rb_obj_frozen_p(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_bool(zr_frozen_p(obj))
  end

  # rb_obj_is_kind_of: whether `obj` is a `klass`, as Qtrue or Qfalse.
  #: (value, value) -> value
  def rb_obj_is_kind_of(obj, klass)
    Machine.gates_enter
    zr_c_entered()
    zr_bool(zr_is_a(obj, klass))
  end

  # rb_obj_is_instance_of: whether `klass` is `obj`'s own class.
  #: (value, value) -> value
  def rb_obj_is_instance_of(obj, klass)
    Machine.gates_enter
    zr_c_entered()
    zr_bool(zr_real_class(obj) == klass)
  end

  # rb_respond_to: whether `obj` responds to the public method `mid`.
  #: (value, word) -> i32
  def rb_respond_to(obj, mid)
    Machine.gates_enter
    zr_c_entered()
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(zr_sym(zr_capi_mid(mid))))
    r = zr_c_result(zr_send(obj, Machine.id(:respond_to?), 1, arg))
    r == QNIL || r == QFALSE ? Machine.i32(0) : Machine.i32(1)
  end

  # rb_ivar_get and rb_iv_get: the instance variable, or nil.
  #: (value, word) -> value
  def rb_ivar_get(obj, mid)
    Machine.gates_enter
    zr_c_entered()
    zr_ivar_get(obj, zr_capi_mid(mid))
  end

  #: (value, ptr) -> value
  def rb_iv_get(obj, name)
    Machine.gates_enter
    zr_c_entered()
    zr_ivar_get(obj, zr_intern(name, zr_cstr_len(name)))
  end

  # rb_ivar_set and rb_iv_set: sets the instance variable, and returns
  # the value.
  #: (value, word, value) -> value
  def rb_ivar_set(obj, mid, v)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_ivar_set(obj, zr_capi_mid(mid), v))
  end

  #: (value, ptr, value) -> value
  def rb_iv_set(obj, name, v)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_ivar_set(obj, zr_intern(name, zr_cstr_len(name)), v))
  end

  # rb_define_const: the constant `name` of `klass`.
  #: (value, ptr, value) -> void
  def rb_define_const(klass, name, v)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_const_set(klass, zr_intern(name, zr_cstr_len(name)), v))
  end

  # rb_const_set: the constant `mid` of `klass`.
  #: (value, word, value) -> void
  def rb_const_set(klass, mid, v)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_const_set(klass, zr_capi_mid(mid), v))
  end

  # rb_const_get and rb_const_get_at: `klass::Name`, through the
  # ancestors or in `klass` alone, with const_missing.
  #: (value, word) -> value
  def rb_const_get(klass, mid)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_const_get(klass, mid, true)
  end

  #: (value, word) -> value
  def rb_const_get_at(klass, mid)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_const_get(klass, mid, false)
  end

  #: (value, word, bool) -> value
  def zr_capi_const_get(klass, mid, inherit)
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(zr_sym(zr_capi_mid(mid))))
    Machine.store64(args, 8, Machine.word(zr_bool(inherit)))
    zr_c_result(zr_send(klass, Machine.id(:const_get), 2, args))
  end

  # rb_class_inherited_p: `mod <= arg`: true, false, or nil when the two
  # are not related.
  #: (value, value) -> value
  def rb_class_inherited_p(mod, arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(mod, Machine.id(:<=), arg)
  end

  # rb_String, rb_Integer, rb_Float, rb_Array: the conversions of Kernel.
  #: (value) -> value
  def rb_String(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_global(G_KERNEL), Machine.id(:String), v)
  end

  #: (value) -> value
  def rb_Integer(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_global(G_KERNEL), Machine.id(:Integer), v)
  end

  #: (value) -> value
  def rb_Float(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_global(G_KERNEL), Machine.id(:Float), v)
  end

  #: (value) -> value
  def rb_Array(v)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_global(G_KERNEL), Machine.id(:Array), v)
  end

  # rb_obj_as_string: `v.to_s`, or rb_any_to_s when that is not a String.
  #: (value) -> value
  def rb_obj_as_string(v)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_obj_as_string(v))
  end

  # rb_inspect: `v.inspect`.
  #: (value) -> value
  def rb_inspect(v)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_inspect(v))
  end

  # rb_class_new_instance: `klass.new(*args)`.
  #: (i32, ptr, value) -> value
  def rb_class_new_instance(argc, argv, klass)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(klass, Machine.id(:new), Machine.sword(argc), argv))
  end

  # rb_obj_call_init: calls `obj.initialize(*args)` with the C method's
  # block.
  #: (value, i32, ptr) -> void
  def rb_obj_call_init(obj, argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send_blk(obj, Machine.id(:initialize), Machine.sword(argc), argv, zr_capi_block()))
  end

  # rb_frame_this_func: the ID of the C method that runs.
  #: () -> word
  def rb_frame_this_func
    Machine.gates_enter
    zr_c_entered()
    zr_capi_id(FrameMeta[Frame[Task[zr_task()].top].meta].name)
  end

  # rb_enumeratorize_with_size: `obj.enum_for(meth, *args)`. A size
  # function is not kept: the Enumerator's size is nil.
  #: (value, value, i32, ptr, ptr) -> value
  def rb_enumeratorize_with_size(obj, meth, argc, argv, size_fn)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_enum_for(obj, zr_sym2id(meth), Machine.sword(argc), argv, Machine.value(QNIL)))
  end

  # rb_proc_call_with_block: `proc.call(*args, &block)`.
  #: (value, i32, ptr, value) -> value
  def rb_proc_call_with_block(proc, argc, argv, block)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_proc_call(proc, Machine.sword(argc), argv, Machine.value(QNIL), block))
  end

  # rb_unexpected_type: CRuby's TypeError for a Value that is not of the
  # type `t` (Check_Type).
  #: (value, i32) -> void
  def rb_unexpected_type(v, t)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    if v == QNIL || v == QTRUE || v == QFALSE
      zr_buf_str(b, zr_c_result(zr_inspect(v)))
    else
      zr_c_result(zr_buf_class_shown(b, v))
    end
    zr_buf_push(b, Machine.bytes(" (expected "), 11)
    zr_capi_type_name(b, Machine.sword(t))
    zr_buf_byte(b, 41)
    zr_c_result(zr_raise_buf(zr_global(G_TYPE_ERROR), b))
  end

  # CRuby's name of the builtin type `t` (rb_builtin_type_name).
  #: (ptr, word) -> void
  def zr_capi_type_name(b, t)
    if t == T_OBJECT
      zr_buf_push(b, Machine.bytes("Object"), 6)
    elsif t == T_CLASS
      zr_buf_push(b, Machine.bytes("Class"), 5)
    elsif t == T_MODULE
      zr_buf_push(b, Machine.bytes("Module"), 6)
    elsif t == T_FLOAT
      zr_buf_push(b, Machine.bytes("Float"), 5)
    elsif t == T_STRING
      zr_buf_push(b, Machine.bytes("String"), 6)
    elsif t == T_REGEXP
      zr_buf_push(b, Machine.bytes("Regexp"), 6)
    elsif t == T_ARRAY
      zr_buf_push(b, Machine.bytes("Array"), 5)
    elsif t == T_HASH
      zr_buf_push(b, Machine.bytes("Hash"), 4)
    elsif t == T_STRUCT
      zr_buf_push(b, Machine.bytes("Struct"), 6)
    elsif t == T_BIGNUM || t == T_FIXNUM
      zr_buf_push(b, Machine.bytes("Integer"), 7)
    elsif t == T_DATA
      zr_buf_push(b, Machine.bytes("Data"), 4)
    elsif t == T_SYMBOL
      zr_buf_push(b, Machine.bytes("Symbol"), 6)
    elsif t == T_NIL
      zr_buf_push(b, Machine.bytes("nil"), 3)
    elsif t == T_TRUE
      zr_buf_push(b, Machine.bytes("true"), 4)
    elsif t == T_FALSE
      zr_buf_push(b, Machine.bytes("false"), 5)
    else
      zr_buf_long(b, t)
    end
  end

  # CRuby's type number of a Struct: zr's Struct is a T_OBJECT.
  T_STRUCT = 9

  # `recv.mid(arg)`, private methods too; a raise unwinds out of C.
  #: (value, word, value) -> value
  def zr_capi_call1(recv, mid, arg)
    args = Machine.slot(8)
    Machine.store64(args, 0, Machine.word(arg))
    zr_c_result(zr_send(recv, mid, 1, args))
  end
end
