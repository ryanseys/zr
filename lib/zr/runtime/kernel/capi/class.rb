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

  # rb_define_module_under: the module `name` in `outer`, new or the one
  # there, which may be a private constant: C reads it as
  # rb_const_get_at does, with no check of its visibility.
  #: (value, ptr) -> value
  def rb_define_module_under(outer, name)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_module_define(outer, zr_capi_name(name), 0))
  end

  # rb_define_class: the toplevel class `name` with the superclass
  # `super_`, new or the one there.
  #: (ptr, value) -> value
  def rb_define_class(name, super_)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_class_define(zr_global(G_OBJECT), zr_capi_name(name), super_, 0))
  end

  # rb_define_class_under: the class `name` in `outer`, as
  # rb_define_module_under finds it.
  #: (value, ptr, value) -> value
  def rb_define_class_under(outer, name, super_)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_class_define(outer, zr_capi_name(name), super_, 0))
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

  # rb_obj_class: the class of `obj`, past singleton classes and module
  # proxies.
  #: (value) -> value
  def rb_obj_class(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_real_class(obj)
  end

  # rb_class2name: the name of `klass` as a C string. A named class keeps
  # its name, so the bytes live as long as the class.
  #: (value) -> ptr
  def rb_class2name(klass)
    Machine.gates_enter
    zr_c_entered()
    RString[zr_class_path(zr_real_class_of_class(klass))].ptr
  end

  # rb_obj_classname: the name of the class of `obj`.
  #: (value) -> ptr
  def rb_obj_classname(obj)
    Machine.gates_enter
    zr_c_entered()
    RString[zr_class_path(zr_real_class(obj))].ptr
  end

  # `klass` past singleton classes and module proxies (rb_class_real).
  #: (value) -> value
  def zr_real_class_of_class(klass)
    while klass != QNIL && (zr_singleton_p(klass) || zr_type(klass) == T_ICLASS)
      klass = RClass[klass].superclass
    end
    klass
  end

  # rb_define_class_id: a new anonymous class under `super_` (Object for
  # 0), which no constant names yet.
  #: (word, value) -> value
  def rb_define_class_id(mid, super_)
    Machine.gates_enter
    zr_c_entered()
    parent = Machine.word(super_) == 0 ? zr_global(G_OBJECT) : super_
    zr_capi_call1(zr_global(G_CLASS), Machine.id(:new), parent)
  end

  # rb_define_module_id: a new anonymous module.
  #: (word) -> value
  def rb_define_module_id(mid)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_global(G_MODULE), Machine.id(:new), 0, Machine.ptr(0)))
  end

  # rb_path2class: the class or module that the path `A::B` names from
  # Object. A part that is missing raises ArgumentError with the path up
  # to it (`undefined class/module A::`), and one that is not a class or a
  # module raises TypeError, as in ruby.
  #: (ptr) -> value
  def rb_path2class(path)
    Machine.gates_enter
    zr_c_entered()
    len = zr_cstr_len(path)
    str = zr_str_new(path, len)
    c = zr_global(G_OBJECT)
    at = 0
    while at < len
      stop = at
      while stop < len && Machine.u8(Machine.load8(path + stop, 0)) != 58
        stop += 1
      end
      upto = stop + 2 <= len ? stop + 2 : stop
      sym = zr_sym(zr_intern(path + at, stop - at))
      if zr_capi_call1(c, Machine.id(:const_defined?), sym) != QTRUE
        zr_capi_path_error(zr_global(G_ARGUMENT_ERROR), Machine.bytes("undefined class/module "), 23, zr_str_new(path, upto), Machine.bytes(""), 0)
      end
      c = zr_capi_call1(c, Machine.id(:const_get), sym)
      if zr_special_p(c) || (zr_type(c) != T_CLASS && zr_type(c) != T_MODULE)
        zr_capi_path_error(zr_global(G_TYPE_ERROR), Machine.bytes(""), 0, str, Machine.bytes(" does not refer to class/module"), 31)
      end
      at = upto
    end
    c
  end

  #: (value, ptr, word, value, ptr, word) -> void
  def zr_capi_path_error(klass, head, hlen, path, tail, tlen)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, head, hlen)
    zr_buf_str(b, path)
    zr_buf_push(b, tail, tlen)
    zr_c_result(zr_raise_buf(klass, b))
  end

  # rb_class_name: the path of `klass` as a String, `#<Class:0x...>` for
  # an anonymous one.
  #: (value) -> value
  def rb_class_name(klass)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_class_path(zr_real_class_of_class(klass)))
  end

  # rb_prepend_module: prepends `mod` to `klass`, as Module#prepend_features
  # does, without the `prepended` hook.
  #: (value, value) -> void
  def rb_prepend_module(klass, mod)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(mod, Machine.id(:prepend_features), klass)
  end

  # rb_define_attr: a reader and a writer of `@name`, as `read` and
  # `write` ask.
  #: (value, ptr, i32, i32) -> void
  def rb_define_attr(klass, name, read, write)
    Machine.gates_enter
    zr_c_entered()
    sym = zr_sym(zr_intern(name, zr_cstr_len(name)))
    if Machine.sword(read) != 0
      zr_capi_call1(klass, Machine.id(:attr_reader), sym)
    end
    if Machine.sword(write) != 0
      zr_capi_call1(klass, Machine.id(:attr_writer), sym)
    end
  end

  # rb_const_defined and rb_const_defined_at: whether `klass` has the
  # constant `mid`, through its ancestors or in itself alone. Like ruby,
  # they give Qtrue (20) as the int for yes, and 0 for no.
  #: (value, word) -> i32
  def rb_const_defined(klass, mid)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_const_defined(klass, mid, true)
  end

  #: (value, word) -> i32
  def rb_const_defined_at(klass, mid)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_const_defined(klass, mid, false)
  end

  #: (value, word, bool) -> i32
  def zr_capi_const_defined(klass, mid, inherit)
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(zr_sym(zr_capi_mid(mid))))
    Machine.store64(args, 8, Machine.word(zr_bool(inherit)))
    Machine.i32(zr_c_result(zr_send(klass, Machine.id(:const_defined?), 2, args)) == QTRUE ? QTRUE : 0)
  end

  # rb_class_superclass, rb_mod_name and rb_mod_ancestors: `superclass`,
  # `name` and `ancestors`.
  #: (value) -> value
  def rb_class_superclass(klass)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(klass, Machine.id(:superclass), 0, Machine.ptr(0)))
  end

  #: (value) -> value
  def rb_mod_name(mod)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(mod, Machine.id(:name), 0, Machine.ptr(0)))
  end

  #: (value) -> value
  def rb_mod_ancestors(mod)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(mod, Machine.id(:ancestors), 0, Machine.ptr(0)))
  end
end
