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
    zr_capi_new_instance(klass, Machine.sword(argc), argv, Machine.i32(0))
  end

  # A new object of `klass`: its allocator, then `initialize` with the
  # arguments and the C method's block, as rb_obj_call_init_kw calls it.
  # Not `klass.new`, which can be the C method that asks (stringio's
  # StringIO.new).
  #: (value, word, ptr, i32) -> value
  def zr_capi_new_instance(klass, argc, argv, kw_splat)
    obj = zr_c_result(zr_class_allocate(klass))
    zr_c_result(zr_capi_send_blk(obj, Machine.id(:initialize), argc, argv, kw_splat, zr_capi_block()))
    obj
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

  # rb_unexpected_object_type: the same TypeError with the expected type
  # named by C, which TypedData_Get_Struct and Check_Type raise.
  #: (value, ptr) -> void
  def rb_unexpected_object_type(v, expected)
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
    zr_buf_push(b, expected, zr_cstr_len(expected))
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
    elsif t == T_FILE
      zr_buf_push(b, Machine.bytes("File"), 4)
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

  # `recv.mid(arg)`, private methods too; a raise unwinds out of C.
  #: (value, word, value) -> value
  def zr_capi_call1(recv, mid, arg)
    args = Machine.slot(8)
    Machine.store64(args, 0, Machine.word(arg))
    zr_c_result(zr_send(recv, mid, 1, args))
  end

  # rb_range_beg_len: the start and length in a sequence of `len` that
  # `range` selects, into `*begp` and `*lenp`: true, false when `range`
  # is not a Range, or nil (with `err`, CRuby's RangeError) when it
  # starts outside. `err` 0 or 2 also stops the length at the end.
  #: (value, ptr, ptr, word, i32) -> value
  def rb_range_beg_len(range, begp, lenp, len, err)
    Machine.gates_enter
    zr_c_entered()
    if zr_special_p(range) || !zr_is_a(range, zr_global(G_RANGE))
      return Machine.value(QFALSE)
    end
    first = zr_c_result(zr_send(range, Machine.id(:begin), 0, Machine.ptr(0)))
    last = zr_c_result(zr_send(range, Machine.id(:end), 0, Machine.ptr(0)))
    excl = zr_c_result(zr_send(range, Machine.id(:exclude_end?), 0, Machine.ptr(0))) == QTRUE
    mode = Machine.sword(err)
    beg = first == QNIL ? 0 : zr_capi_long(first)
    stop = last == QNIL ? 0 - 1 : zr_capi_long(last)
    if last == QNIL
      excl = false
    end
    if beg < 0
      beg += len
    end
    if beg >= 0
      if stop < 0
        stop += len
      end
      if !excl
        stop += 1
      end
      if (mode == 0 || mode == 2) && stop > len
        stop = len
      end
      if !((mode == 0 || mode == 2) && beg > len)
        Machine.store64(begp, 0, beg)
        Machine.store64(lenp, 0, stop - beg < 0 ? 0 : stop - beg)
        return Machine.value(QTRUE)
      end
    end
    if mode != 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_str(b, zr_c_result(zr_inspect(range)))
      zr_buf_push(b, Machine.bytes(" out of range"), 13)
      zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:RangeError)), b))
    end
    Machine.value(QNIL)
  end

  # rb_attr_get: the instance variable `mid` (`@name`), or nil.
  #: (value, word) -> value
  def rb_attr_get(obj, mid)
    Machine.gates_enter
    zr_c_entered()
    zr_ivar_get(obj, zr_capi_mid(mid))
  end

  # rb_obj_is_proc: whether `obj` is a Proc, as Qtrue or Qfalse.
  #: (value) -> value
  def rb_obj_is_proc(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_bool(!zr_special_p(obj) && zr_is_a(obj, zr_global(G_PROC)))
  end

  # rb_class_new_instance_kw: `klass.new(*args)`, the last argument the
  # keywords when `kw_splat` is not 0.
  #: (i32, ptr, value, i32) -> value
  def rb_class_new_instance_kw(argc, argv, klass, kw_splat)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_new_instance(klass, Machine.sword(argc), argv, kw_splat)
  end

  # rb_class_new_instance_pass_kw: the same, with keywords when the C
  # method got them.
  #: (i32, ptr, value) -> value
  def rb_class_new_instance_pass_kw(argc, argv, klass)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_new_instance(klass, Machine.sword(argc), argv, Machine.i32(Task[zr_task()].c_keywords))
  end

  # rb_require: `require feature`, Qtrue or Qfalse.
  #: (ptr) -> value
  def rb_require(feature)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_global(G_KERNEL), Machine.id(:require), zr_str_new(feature, zr_cstr_len(feature)))
  end

  # The builtin type of `v` that C's TYPE() reads (T_STRING, T_NIL...).
  #: (value) -> word
  def zr_capi_builtin_type(v)
    if v == QNIL
      return T_NIL
    end
    if v == QTRUE
      return T_TRUE
    end
    if v == QFALSE
      return T_FALSE
    end
    if zr_fixnum_p(v)
      return T_FIXNUM
    end
    if zr_flonum_p(v)
      return T_FLOAT
    end
    if zr_symbol_p(v)
      return T_SYMBOL
    end
    t = RBasic[v].flags & T_MASK
    # An IO is CRuby's T_FILE, which C reaches through its companion.
    if t == T_OBJECT && zr_is_a(v, zr_core_class(Machine.id(:IO)))
      return T_FILE
    end
    t
  end

  # The type that ruby gives `v` where zr's own tag differs: a Proc, a
  # Method or a Fiber is T_DATA in ruby, and an Exception T_OBJECT. A
  # conversion checks this (json's rb_convert_type(x, T_DATA, "Proc",
  # "to_proc")); C still cannot read such an object as a T_DATA.
  #: (value) -> word
  def zr_capi_ruby_type(v)
    t = zr_capi_builtin_type(v)
    if t == T_PROC || t == T_METHOD || t == T_FIBER
      return T_DATA
    end
    t == T_EXCEPTION ? T_OBJECT : t
  end

  # rb_convert_type: `val` when it is of the builtin type `type`, else
  # what its conversion `method` (`to_str`) gives, which must be of that
  # type. Raises TypeError, with ruby's message, when `val` has no such
  # method or the method gives another type.
  #: (value, i32, ptr, ptr) -> value
  def rb_convert_type(val, type, tname, method)
    Machine.gates_enter
    zr_c_entered()
    t = Machine.sword(type)
    if zr_capi_ruby_type(val) == t
      return val
    end
    mid = zr_intern(method, zr_cstr_len(method))
    v = zr_capi_convert(val, tname, zr_cstr_len(tname), mid, true)
    zr_capi_converted(val, v, t, tname, zr_cstr_len(tname), mid)
  end

  # rb_check_convert_type: the same, but nil when `val` has no such
  # method or the method gives nil.
  #: (value, i32, ptr, ptr) -> value
  def rb_check_convert_type(val, type, tname, method)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_convert(val, Machine.sword(type), tname, zr_cstr_len(tname), zr_intern(method, zr_cstr_len(method)))
  end

  # rb_check_array_type: `val` as an Array through `to_ary`, or nil.
  #: (value) -> value
  def rb_check_array_type(val)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_convert(val, T_ARRAY, Machine.bytes("Array"), 5, Machine.id(:to_ary))
  end

  # rb_check_hash_type: `val` as a Hash through `to_hash`, or nil.
  #: (value) -> value
  def rb_check_hash_type(val)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_convert(val, T_HASH, Machine.bytes("Hash"), 4, Machine.id(:to_hash))
  end

  #: (value, word, ptr, word, word) -> value
  def zr_capi_check_convert(val, t, tname, tlen, mid)
    if zr_capi_ruby_type(val) == t && t != T_DATA
      return val
    end
    v = zr_capi_convert(val, tname, tlen, mid, false)
    if v == QNIL
      return v
    end
    zr_capi_converted(val, v, t, tname, tlen, mid)
  end

  # `val.mid`: when `val` does not respond to it, a TypeError when
  # `raise` says so, else nil. `tname` is the type's name, `tlen` bytes.
  #: (value, ptr, word, word, bool) -> value
  def zr_capi_convert(val, tname, tlen, mid, raise)
    if zr_c_result(zr_check_funcall(val, mid)) == QTRUE
      return zr_c_result(zr_send(val, mid, 0, Machine.ptr(0)))
    end
    if !raise
      return Machine.value(QNIL)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    if zr_capi_implicit_p(mid)
      zr_buf_push(b, Machine.bytes("no implicit conversion of "), 26)
    else
      zr_buf_push(b, Machine.bytes("can't convert "), 14)
    end
    if val == QNIL || val == QTRUE || val == QFALSE
      zr_buf_str(b, zr_c_result(zr_inspect(val)))
    else
      zr_buf_str(b, zr_c_result(zr_inspect(zr_real_class(val))))
    end
    zr_buf_push(b, Machine.bytes(" into "), 6)
    zr_buf_push(b, tname, tlen)
    zr_c_result(zr_raise_new(zr_global(G_TYPE_ERROR), zr_buf_take_at(b, ENC_UTF8)))
  end

  # Whether `mid` is one of ruby's implicit conversions, whose TypeError
  # says `no implicit conversion`.
  #: (word) -> bool
  def zr_capi_implicit_p(mid)
    mid == Machine.id(:to_int) || mid == Machine.id(:to_ary) || mid == Machine.id(:to_str) || mid == Machine.id(:to_sym) ||
      mid == Machine.id(:to_hash) || mid == Machine.id(:to_proc) || mid == Machine.id(:to_io)
  end

  # `v`, which `val.mid` gave, when it is of the builtin type `t`; else
  # ruby's TypeError, `can't convert X into Array (X#to_ary gives Y)`.
  #: (value, value, word, ptr, word, word) -> value
  def zr_capi_converted(val, v, t, tname, tlen, mid)
    if zr_capi_ruby_type(v) == t
      return v
    end
    shown = zr_c_result(zr_inspect(val == QNIL || val == QTRUE || val == QFALSE ? val : zr_real_class(val)))
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("can't convert "), 14)
    zr_buf_str(b, shown)
    zr_buf_push(b, Machine.bytes(" into "), 6)
    zr_buf_push(b, tname, tlen)
    zr_buf_push(b, Machine.bytes(" ("), 2)
    zr_buf_str(b, shown)
    zr_buf_byte(b, 35)
    zr_buf_str(b, zr_c_result(zr_send(zr_sym(mid), Machine.id(:to_s), 0, Machine.ptr(0))))
    zr_buf_push(b, Machine.bytes(" gives "), 7)
    zr_buf_cname(b, v)
    zr_buf_byte(b, 41)
    zr_c_result(zr_raise_new(zr_global(G_TYPE_ERROR), zr_buf_take_at(b, ENC_UTF8)))
  end

  # rb_equal: whether `a == b`, true for the same object, as Qtrue or
  # Qfalse.
  #: (value, value) -> value
  def rb_equal(a, b)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_rb_equal(a, b))
  end

  # rb_error_frozen_object: raises FrozenError for changing `obj`.
  #: (value) -> void
  def rb_error_frozen_object(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_frozen_error(obj))
  end

  # rb_obj_dup: `obj.dup`.
  #: (value) -> value
  def rb_obj_dup(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(obj, Machine.id(:dup), 0, Machine.ptr(0)))
  end

  # rb_obj_alloc: a new `klass` from its allocator, not initialized.
  #: (value) -> value
  def rb_obj_alloc(klass)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_class_allocate(klass))
  end

  # rb_obj_hide: ruby hides `obj` from ObjectSpace by clearing its class;
  # zr keeps it as it is, and returns it.
  #: (value) -> value
  def rb_obj_hide(obj)
    Machine.gates_enter
    zr_c_entered()
    obj
  end

  # rb_obj_freeze_inline: freezes `obj` (the OBJ_FREEZE macro).
  #: (value) -> void
  def rb_obj_freeze_inline(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_obj_freeze(obj, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL))
  end

  # rb_obj_encoding: the Encoding of `obj`; TypeError for an object with
  # none.
  #: (value) -> value
  def rb_obj_encoding(obj)
    Machine.gates_enter
    zr_c_entered()
    index = zr_capi_obj_enc_index(obj)
    if index < 0
      zr_c_raise(zr_global(G_TYPE_ERROR), Machine.bytes("unknown encoding"), 16)
    end
    zr_capi_encoding_object(index)
  end

  # rb_ivar_defined: whether `obj` has the instance variable `mid`.
  #: (value, word) -> value
  def rb_ivar_defined(obj, mid)
    Machine.gates_enter
    zr_c_entered()
    zr_ivar_defined(obj, zr_capi_mid(mid))
  end

  # rb_ivar_count: the number of `obj`'s instance variables.
  #: (value) -> word
  def rb_ivar_count(obj)
    Machine.gates_enter
    zr_c_entered()
    RArray[zr_capi_ivar_names(obj)].len
  end

  # rb_ivar_foreach: `fn(id, value, arg)` for each instance variable of
  # `obj`, until one returns ST_STOP.
  #: (value, ptr, word) -> void
  def rb_ivar_foreach(obj, fn, arg)
    Machine.gates_enter
    zr_c_entered()
    names = zr_capi_ivar_names(obj)
    argv = Machine.slot(64)
    i = 0
    while i < RArray[names].len
      id = zr_sym2id(zr_ary_at(names, i))
      Machine.store64(argv, 0, zr_capi_id(id))
      Machine.store64(argv, 8, Machine.word(zr_ivar_get(obj, id)))
      Machine.store64(argv, 16, arg)
      r = zr_call_c(fn, argv, 3)
      if r == QUNDEF
        zr_c_result(Machine.value(QUNDEF))
      end
      if (r & 0xffffffff) == ST_STOP
        return
      end
      i += 1
    end
  end

  # The names of `obj`'s instance variables, as Symbols.
  #: (value) -> value
  def zr_capi_ivar_names(obj)
    zr_c_result(zr_obj_instance_variables(obj, 0, Machine.ptr(0), Machine.value(QNIL), Machine.value(QNIL)))
  end

  # rb_cvar_get: the class variable `mid` of `klass`.
  #: (value, word) -> value
  def rb_cvar_get(klass, mid)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(klass, Machine.id(:class_variable_get), zr_sym(zr_capi_mid(mid)))
  end

  # rb_extend_object: adds `mod` to `obj`'s singleton class, as
  # Module#extend_object does.
  #: (value, value) -> void
  def rb_extend_object(obj, mod)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(mod, Machine.id(:extend_object), obj)
  end

  # rb_singleton_class: `obj`'s singleton class, made when it has none.
  #: (value) -> value
  def rb_singleton_class(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_singleton_class(obj))
  end

  # rb_method_boundp: 1 when instances of `klass` have the method `mid`:
  # a public or protected one when `ex` is not 0, any one when it is.
  #: (value, word, i32) -> i32
  def rb_method_boundp(klass, mid, ex)
    Machine.gates_enter
    zr_c_entered()
    sym = zr_sym(zr_capi_mid(mid))
    if zr_capi_call1(klass, Machine.id(:method_defined?), sym) == QTRUE
      return Machine.i32(1)
    end
    if Machine.sword(ex) == 0 && zr_capi_call1(klass, Machine.id(:private_method_defined?), sym) == QTRUE
      return Machine.i32(1)
    end
    Machine.i32(0)
  end

  # rb_obj_method_arity: the arity of `obj`'s method `mid`.
  #: (value, word) -> i32
  def rb_obj_method_arity(obj, mid)
    Machine.gates_enter
    zr_c_entered()
    m = zr_capi_call1(obj, Machine.id(:method), zr_sym(zr_capi_mid(mid)))
    Machine.i32(zr_fix2long(zr_c_result(zr_send(m, Machine.id(:arity), 0, Machine.ptr(0)))))
  end

  # rb_apply: `recv.mid(*args)`, private methods too.
  #: (value, word, value) -> value
  def rb_apply(recv, mid, args)
    Machine.gates_enter
    zr_c_entered()
    # A copy: the call may change `args`.
    copy = zr_c_result(zr_send(args, Machine.id(:dup), 0, Machine.ptr(0)))
    zr_c_result(zr_send(recv, zr_capi_mid(mid), RArray[copy].len, RArray[copy].ptr))
  end

  # rb_check_type: raises TypeError unless `v` is of the builtin type `t`
  # (Check_Type).
  #: (value, i32) -> void
  def rb_check_type(v, t)
    Machine.gates_enter
    zr_c_entered()
    if zr_capi_builtin_type(v) != Machine.sword(t)
      rb_unexpected_type(v, t)
    end
  end

  # rb_gv_get and rb_gv_set: the global variable `name`, with or without
  # its `$`.
  #: (ptr) -> value
  def rb_gv_get(name)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_gvar_get(zr_capi_gvar_id(name)))
  end

  #: (ptr, value) -> value
  def rb_gv_set(name, v)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_gvar_set(zr_capi_gvar_id(name), v))
  end

  # The id of the global variable `name`, `$` first.
  #: (ptr) -> word
  def zr_capi_gvar_id(name)
    len = zr_cstr_len(name)
    if len > 0 && Machine.u8(Machine.load8(name, 0)) == 36
      return zr_intern(name, len)
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_byte(b, 36)
    zr_buf_push(b, name, len)
    id = zr_intern(Buf[b].ptr, Buf[b].len)
    zr_buf_free(b)
    id
  end

  # rb_marshal_dump: `Marshal.dump(obj)`, or into `port` when it is not
  # nil.
  #: (value, value) -> value
  def rb_marshal_dump(obj, port)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(obj))
    Machine.store64(args, 8, Machine.word(port))
    zr_c_result(zr_send(zr_core_class(Machine.id(:Marshal)), Machine.id(:dump), port == QNIL ? 1 : 2, args))
  end

  # rb_marshal_load: `Marshal.load(port)`.
  #: (value) -> value
  def rb_marshal_load(port)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_core_class(Machine.id(:Marshal)), Machine.id(:load), port)
  end

  # rb_cmpint: -1, 0 or 1 for what `a <=> b` gave as `val`; ArgumentError
  # for nil, as Comparable does.
  #: (value, value, value) -> i32
  def rb_cmpint(val, a, b)
    Machine.gates_enter
    zr_c_entered()
    if val == QNIL
      zr_c_result(zr_cmperr(a, b))
    end
    if zr_fixnum_p(val)
      n = zr_fix2long(val)
      return Machine.i32(n > 0 ? 1 : n < 0 ? 0 - 1 : 0)
    end
    if zr_capi_call1(val, Machine.id(:>), zr_fix(0)) == QTRUE
      return Machine.i32(1)
    end
    Machine.i32(zr_capi_call1(val, Machine.id(:<), zr_fix(0)) == QTRUE ? 0 - 1 : 0)
  end

  # rb_any_to_s: `#<Name:0x...>`, as Kernel#to_s writes any object.
  #: (value) -> value
  def rb_any_to_s(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_any_to_s(obj)
  end

  # rb_obj_id: `obj.__id__`.
  #: (value) -> value
  def rb_obj_id(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(obj, Machine.id(:__id__), 0, Machine.ptr(0)))
  end

  # rb_class_attached_object: the object of the singleton class `klass`
  # (Class#attached_object, which raises for any other class).
  #: (value) -> value
  def rb_class_attached_object(klass)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(klass, Machine.id(:attached_object), 0, Machine.ptr(0)))
  end

  # rb_obj_clone: `obj.clone`.
  #: (value) -> value
  def rb_obj_clone(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(obj, Machine.id(:clone), 0, Machine.ptr(0)))
  end

  # rb_obj_init_copy: Object#initialize_copy, which a C `initialize_copy`
  # calls first: nothing for the object itself, else the checks that it
  # can take the copy.
  #: (value, value) -> value
  def rb_obj_init_copy(obj, orig)
    Machine.gates_enter
    zr_c_entered()
    if obj == orig
      return obj
    end
    if zr_modify_frozen_p(obj)
      zr_c_result(zr_frozen_error(obj))
    end
    if zr_real_class(obj) != zr_real_class(orig)
      zr_c_raise(zr_global(G_TYPE_ERROR), Machine.bytes("initialize_copy should take same class object"), 45)
    end
    obj
  end

  # rb_error_frozen: FrozenError for changing the frozen `what`.
  #: (ptr) -> void
  def rb_error_frozen(what)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("can't modify frozen "), 20)
    zr_buf_push(b, what, zr_cstr_len(what))
    zr_c_result(zr_raise_buf(zr_core_class(Machine.id(:FrozenError)), b))
  end

  # rb_eql: whether `a` and `b` are the same object or `a.eql?(b)`, as 1
  # or 0.
  #: (value, value) -> i32
  def rb_eql(a, b)
    Machine.gates_enter
    zr_c_entered()
    if a == b || zr_capi_call1(a, Machine.id(:eql?), b) == QTRUE
      return Machine.i32(1)
    end
    Machine.i32(0)
  end

  # rb_obj_method: `obj.method(name)`.
  #: (value, value) -> value
  def rb_obj_method(obj, name)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(obj, Machine.id(:method), name)
  end

  # rb_memerror: NoMemoryError, as when an allocation fails.
  #: () -> void
  def rb_memerror
    Machine.gates_enter
    zr_c_entered()
    zr_c_raise(zr_core_class(Machine.id(:NoMemoryError)), Machine.bytes("failed to allocate memory"), 25)
  end

  # rb_hash: `obj.hash`.
  #: (value) -> value
  def rb_hash(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(obj, Machine.id(:hash), 0, Machine.ptr(0)))
  end

  # rb_to_int and rb_check_to_integer: `val` as an Integer through its
  # conversion; rb_check_to_integer gives nil where rb_to_int raises.
  #: (value) -> value
  def rb_to_int(val)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_to_int(val)
  end

  #: (value) -> value
  def zr_capi_to_int(val)
    if zr_fixnum_p(val) || zr_big_p(val)
      return val
    end
    v = zr_capi_convert(val, Machine.bytes("Integer"), 7, Machine.id(:to_int), true)
    if zr_fixnum_p(v) || zr_big_p(v)
      return v
    end
    zr_capi_converted(val, v, T_FIXNUM, Machine.bytes("Integer"), 7, Machine.id(:to_int))
  end

  #: (value, ptr) -> value
  def rb_check_to_integer(val, method)
    Machine.gates_enter
    zr_c_entered()
    if zr_fixnum_p(val) || zr_big_p(val)
      return val
    end
    mid = zr_intern(method, zr_cstr_len(method))
    v = zr_capi_convert(val, Machine.bytes("Integer"), 7, mid, false)
    zr_fixnum_p(v) || zr_big_p(v) ? v : Machine.value(QNIL)
  end

  # rb_obj_instance_variables: Object#instance_variables.
  #: (value) -> value
  def rb_obj_instance_variables(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(obj, Machine.id(:instance_variables), 0, Machine.ptr(0)))
  end

  # rb_objspace_internal_object_p: no object that C sees is internal to
  # zr: each is a program's.
  #: (value) -> i32
  def rb_objspace_internal_object_p(obj)
    Machine.gates_enter
    zr_c_entered()
    Machine.i32(0)
  end

  # rb_get_argv: ARGV.
  #: () -> value
  def rb_get_argv
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_global(G_OBJECT), Machine.id(:const_get), 1, zr_capi_one(zr_sym(Machine.id(:ARGV)))))
  end

  # A one-word argv holding `v`.
  #: (value) -> ptr
  def zr_capi_one(v)
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(v))
    arg
  end

  # rb_assert_failure: RUBY_ASSERT's report, after which the process ends.
  #: (ptr, i32, ptr, ptr) -> void
  def rb_assert_failure(file, line, name, expr)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("Assertion Failed: "), 18)
    zr_buf_push(b, file, zr_cstr_len(file))
    zr_buf_byte(b, 58)
    zr_buf_long(b, Machine.sword(line))
    zr_buf_byte(b, 58)
    if name != 0
      zr_buf_push(b, name, zr_cstr_len(name))
    end
    zr_buf_byte(b, 58)
    zr_buf_push(b, expr, zr_cstr_len(expr))
    zr_buf_byte(b, 10)
    zr_bug(Buf[b].ptr, Buf[b].len)
  end

  # rb_copy_generic_ivar: `dest` takes the instance variables of `obj`,
  # the hidden ones too, when `obj` keeps them outside its cell: a String,
  # an Array or a T_DATA, not a plain object or a class, whose variables
  # are its own (`clone` copies them). A frozen `dest` raises.
  #: (value, value) -> void
  def rb_copy_generic_ivar(dest, obj)
    Machine.gates_enter
    zr_c_entered()
    if zr_modify_frozen_p(dest)
      zr_c_result(zr_frozen_error(dest))
    end
    if zr_special_p(obj)
      return
    end
    type = zr_type(obj)
    if type == T_OBJECT || type == T_CLASS || type == T_MODULE || type == T_ICLASS
      return
    end
    t = zr_ivtab(obj)
    if t == 0
      return
    end
    i = 0
    while i < IvTab[t].len
      row = IvTab[t].rows + (i * IvEntry.size)
      zr_c_result(zr_ivar_set(dest, IvEntry[row].id, IvEntry[row].value))
      i += 1
    end
  end
end
