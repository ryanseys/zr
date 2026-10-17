module Zr::Kern
  # The C API's T_DATA objects (data_object.rb), and the allocation
  # functions that make them for a class.

  # rb_data_typed_object_wrap: a T_DATA of `klass` (0 for a hidden one)
  # whose struct is `datap`, of the type `type`.
  #: (value, ptr, ptr) -> value
  def rb_data_typed_object_wrap(klass, datap, type)
    Machine.gates_enter
    zr_c_entered()
    if (DataType[type].flags & TYPED_EMBEDDABLE) != 0
      zr_c_raise(zr_global(G_TYPE_ERROR), Machine.bytes("Cannot wrap an embeddable TypedData"), 35)
    end
    zr_capi_typed_data(klass, datap, type)
  end

  # rb_data_typed_object_zalloc: the same, with a new zeroed struct of
  # `size` bytes. zr never embeds the struct in the cell, which CRuby's
  # RTYPEDDATA_GET_DATA allows for any type.
  #: (value, word, ptr) -> value
  def rb_data_typed_object_zalloc(klass, size, type)
    Machine.gates_enter
    zr_c_entered()
    flags = DataType[type].flags
    if (flags & TYPED_EMBEDDABLE) != 0 && (flags & TYPED_FREES_NOW) == 0
      zr_c_raise(zr_global(G_TYPE_ERROR), Machine.bytes("Embeddable TypedData must be freed immediately"), 46)
    end
    v = zr_capi_typed_data(klass, Machine.ptr(0), type)
    RTypedData[v].data = zr_capi_zalloc(size)
    v
  end

  # rb_check_typeddata: the struct of `obj`, a T_DATA of `type` or of a
  # type whose `parent` chain reaches it, or CRuby's TypeError.
  #: (value, ptr) -> ptr
  def rb_check_typeddata(obj, type)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    if zr_type(obj) == T_DATA
      if zr_capi_type_inherits(zr_data_type(obj), type)
        zr_buf_free(b)
        return zr_data_ptr(obj)
      end
      name = DataType[zr_data_type(obj)].wrap_struct_name
      zr_buf_push(b, name, zr_cstr_len(name))
    elsif obj == QNIL || obj == QTRUE || obj == QFALSE
      zr_buf_str(b, zr_c_result(zr_inspect(obj)))
    else
      zr_c_result(zr_buf_class_shown(b, obj))
    end
    zr_buf_push(b, Machine.bytes(" (expected "), 11)
    zr_buf_push(b, DataType[type].wrap_struct_name, zr_cstr_len(DataType[type].wrap_struct_name))
    zr_buf_byte(b, 41)
    zr_c_result(zr_raise_buf(zr_global(G_TYPE_ERROR), b))
    Machine.ptr(0)
  end

  # rb_unexpected_typeddata: the TypeError of a T_DATA of the type
  # `actual` where the type `expected` was wanted, which the headers'
  # TypedData_Get_Struct raises.
  #: (ptr, ptr) -> void
  def rb_unexpected_typeddata(actual, expected)
    Machine.gates_enter
    zr_c_entered()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
    zr_buf_push(b, DataType[actual].wrap_struct_name, zr_cstr_len(DataType[actual].wrap_struct_name))
    zr_buf_push(b, Machine.bytes(" (expected "), 11)
    zr_buf_push(b, DataType[expected].wrap_struct_name, zr_cstr_len(DataType[expected].wrap_struct_name))
    zr_buf_byte(b, 41)
    zr_c_result(zr_raise_buf(zr_global(G_TYPE_ERROR), b))
  end

  # rb_typeddata_is_kind_of: 1 when `obj` is a T_DATA of `type` or of a
  # type that inherits it, else 0.
  #: (value, ptr) -> i32
  def rb_typeddata_is_kind_of(obj, type)
    Machine.gates_enter
    zr_c_entered()
    if zr_type(obj) == T_DATA && zr_capi_type_inherits(zr_data_type(obj), type)
      return Machine.i32(1)
    end
    Machine.i32(0)
  end

  # rb_typeddata_inherited_p: whether `parent` is `child` or on its
  # parent chain.
  #: (ptr, ptr) -> i32
  def rb_typeddata_inherited_p(child, parent)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_type_inherits(child, parent) ? Machine.i32(1) : Machine.i32(0)
  end

  # rb_define_alloc_func: `klass.allocate` (and so `new`) calls the C
  # function `fn` with the class.
  #: (value, ptr) -> void
  def rb_define_alloc_func(klass, fn)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_class(klass)
    ClassExt[RClass[klass].ext].alloc = Machine.word(fn)
  end

  # rb_undef_alloc_func: `klass` and its subclasses have no allocator.
  #: (value) -> void
  def rb_undef_alloc_func(klass)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_check_class(klass)
    zr_undef_allocator(klass)
  end

  # The typed T_DATA of `klass` with the struct `datap`. One whose C
  # stores skip the write barrier goes on the unprotected list, as CRuby
  # makes it a WB-unprotected object.
  #: (value, ptr, ptr) -> value
  def zr_capi_typed_data(klass, datap, type)
    zr_capi_data_check(klass)
    v = zr_alloc(T_DATA, klass, RTypedData.size)
    RTypedData[v].fields_obj = Machine.value(QFALSE)
    RTypedData[v].type = Machine.word(type)
    RTypedData[v].data = datap
    if (DataType[type].flags & TYPED_WB_PROTECTED) == 0 && DataType[type].dmark != 0
      zr_unprotected_add(v)
    end
    v
  end

  # rb_data_object_check: a class that still allocates plain objects loses
  # its allocator, with CRuby's warning, because `new` would make an
  # object with no struct.
  #: (value) -> void
  def zr_capi_data_check(klass)
    if klass == QFALSE || klass == zr_global(G_OBJECT) || zr_alloc_kind(klass) != ALLOC_OBJECT
      return
    end
    zr_undef_allocator(klass)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("undefining the allocator of T_DATA class "), 41)
    zr_buf_class(b, klass)
    zr_warn_here(Buf[b].ptr, Buf[b].len)
    zr_buf_free(b)
  end

  # Whether `child` is `parent`, or `parent` is on its parent chain.
  #: (ptr, ptr) -> bool
  def zr_capi_type_inherits(child, parent)
    while child != 0
      if child == parent
        return true
      end
      child = DataType[child].parent
    end
    false
  end

  # A zeroed struct of `size` bytes, as ruby_xcalloc(1, size) gives.
  #: (word) -> ptr
  def zr_capi_zalloc(size)
    p = zr_xmalloc(size)
    Libc.memset(p, Machine.i32(0), size)
    p
  end

  # Check_Type(klass, T_CLASS), as rb_define_alloc_func does.
  #: (value) -> void
  def zr_capi_check_class(klass)
    if zr_type(klass) != T_CLASS
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("wrong argument type "), 20)
      zr_c_result(zr_buf_class_shown(b, klass))
      zr_buf_push(b, Machine.bytes(" (expected Class)"), 17)
      zr_c_result(zr_raise_buf(zr_global(G_TYPE_ERROR), b))
    end
  end

  # rb_get_alloc_func: the allocator that rb_define_alloc_func gave
  # `klass` or its nearest ancestor, or NULL when none of them has one.
  #: (value) -> ptr
  def rb_get_alloc_func(klass)
    Machine.gates_enter
    zr_c_entered()
    k = klass
    while !zr_special_p(k) && zr_type(k) == T_CLASS
      ext = RClass[k].ext
      if ext != 0 && ClassExt[ext].alloc != 0
        return Machine.ptr(ClassExt[ext].alloc)
      end
      k = zr_c_result(zr_send(k, Machine.id(:superclass), 0, Machine.ptr(0)))
    end
    Machine.ptr(0)
  end
end
