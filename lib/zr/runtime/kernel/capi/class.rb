module Zr::Kern
  # The C API's definitions: modules, classes and methods, as an
  # extension's Init makes them.

  # rb_define_module: the toplevel module `name`, new or the one there.
  #: (ptr) -> value
  def rb_define_module(name)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_module_define(zr_global(G_OBJECT), zr_capi_name(name), 0))
  end

  # rb_define_module_under: the module `name` in `outer`.
  #: (value, ptr) -> value
  def rb_define_module_under(outer, name)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_module_define(outer, zr_capi_name(name), 1))
  end

  # rb_define_class: the toplevel class `name` with the superclass
  # `super_`, new or the one there.
  #: (ptr, value) -> value
  def rb_define_class(name, super_)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_class_define(zr_global(G_OBJECT), zr_capi_name(name), super_, 0))
  end

  # rb_define_class_under: the class `name` in `outer`.
  #: (value, ptr, value) -> value
  def rb_define_class_under(outer, name, super_)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_class_define(outer, zr_capi_name(name), super_, 1))
  end

  # rb_define_method: a public method of `klass` whose body is the C
  # function `fn`, which takes `arity` arguments (rb_define_method's -2
  # to 15).
  #: (value, ptr, ptr, i32) -> void
  def rb_define_method(klass, name, fn, arity)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_define(klass, name, fn, Machine.sword(arity), VIS_PUBLIC)
  end

  #: (value, ptr, ptr, i32) -> void
  def rb_define_private_method(klass, name, fn, arity)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_define(klass, name, fn, Machine.sword(arity), VIS_PRIVATE)
  end

  #: (value, ptr, ptr, i32) -> void
  def rb_define_protected_method(klass, name, fn, arity)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_define(klass, name, fn, Machine.sword(arity), VIS_PROTECTED)
  end

  # rb_define_singleton_method: a method of `obj`'s singleton class.
  #: (value, ptr, ptr, i32) -> void
  def rb_define_singleton_method(obj, name, fn, arity)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_define(zr_c_result(zr_singleton_class(obj)), name, fn, Machine.sword(arity), VIS_PUBLIC)
  end

  # rb_define_module_function: a private method of `mod`, and a public
  # one of its singleton class, as `module_function` makes them.
  #: (value, ptr, ptr, i32) -> void
  def rb_define_module_function(mod, name, fn, arity)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_define(mod, name, fn, Machine.sword(arity), VIS_PRIVATE)
    zr_capi_define(zr_c_result(zr_singleton_class(mod)), name, fn, Machine.sword(arity), VIS_PUBLIC)
  end

  # rb_define_global_function: a module function of Kernel.
  #: (ptr, ptr, i32) -> void
  def rb_define_global_function(name, fn, arity)
    Machine.gates_enter
    zr_c_entered()
    mod = zr_global(G_KERNEL)
    zr_capi_define(mod, name, fn, Machine.sword(arity), VIS_PRIVATE)
    zr_capi_define(zr_c_result(zr_singleton_class(mod)), name, fn, Machine.sword(arity), VIS_PUBLIC)
  end

  # rb_define_alias: `new_name` for the method `old_name` of `klass`.
  #: (value, ptr, ptr) -> void
  def rb_define_alias(klass, new_name, old_name)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_alias(klass, zr_capi_name(new_name), zr_capi_name(old_name)))
  end

  # rb_include_module: includes `mod` in `klass`.
  #: (value, value) -> void
  def rb_include_module(klass, mod)
    Machine.gates_enter
    zr_c_entered()
    zr_include_module(klass, mod)
  end

  # The symbol id of the C string `name`.
  #: (ptr) -> word
  def zr_capi_name(name)
    zr_intern(name, zr_cstr_len(name))
  end

  # A method whose body is the C function `fn`. It is a builtin whose
  # function is zr_cfunc_call; the method's FrameMeta keeps `fn` and the
  # arity, which says how C takes the arguments (method.rb). Its entry's
  # `body` is `fn` too, so two methods of one C function are the same
  # method, as two definitions of one def are.
  #: (value, ptr, ptr, word, word) -> void
  def zr_capi_define(klass, name, fn, arity, vis)
    if arity < 0 - 2 || arity > 15
      zr_capi_arity_error(arity)
    end
    mid = zr_capi_name(name)
    meta = zr_meta_new()
    FrameMeta[meta].arity = arity
    FrameMeta[meta].fn = fn
    # The entry's arity is what Method#arity shows: -1 for -2, as ruby
    # gives any count.
    shown = arity == 0 - 2 ? 0 - 1 : arity
    zr_c_result(zr_define_method_as(klass, mid, Machine.addr(:zr_cfunc_call), shown, KIND_BUILTIN, meta, Machine.value(QNIL), vis))
    e = zr_find_method_at(zr_origin(klass), mid)
    if e != 0
      MEntry[e].body = fn
    end
  end

  # rb_define_method's `arity out of range: N for -2..15` (ArgumentError).
  #: (word) -> void
  def zr_capi_arity_error(arity)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("arity out of range: "), 20)
    zr_buf_long(b, arity)
    zr_buf_push(b, Machine.bytes(" for -2..15"), 11)
    zr_c_result(zr_raise_buf(zr_global(G_ARGUMENT_ERROR), b))
  end
end
