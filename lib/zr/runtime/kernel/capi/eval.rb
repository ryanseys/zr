module Zr::Kern
  # The C API's evaluation of Ruby source and its loads of files, each one
  # the Kernel method of its name on the main object. The `_protect`
  # forms stop any unwind, as rb_protect does: `*state` gets its tag.

  # rb_eval_string: `eval(text)` of the C string `text`, at the top level.
  #: (ptr) -> value
  def rb_eval_string(text)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_capi_eval(text))
  end

  #: (ptr, ptr) -> value
  def rb_eval_string_protect(text, state)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_protected(zr_capi_eval(text), state)
  end

  # rb_load: `load(path, wrap)`; a `wrap` that is not 0 runs the file
  # under an anonymous module.
  #: (value, i32) -> void
  def rb_load(path, wrap)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_capi_load(path, wrap))
  end

  # rb_load_protect: the same, protected; unlike rb_protect, it leaves
  # `*state` as it was when the load ends normally.
  #: (value, i32, ptr) -> void
  def rb_load_protect(path, wrap, state)
    Machine.gates_enter
    zr_c_entered()
    if zr_capi_load(path, wrap) == QUNDEF
      zr_capi_protected(Machine.value(QUNDEF), state)
    end
  end

  #: (ptr) -> value
  def zr_capi_eval(text)
    arg = Machine.slot(8)
    Machine.store64(arg, 0, Machine.word(zr_str_new(text, zr_cstr_len(text))))
    zr_send(zr_global(G_MAIN), Machine.id(:eval), 1, arg)
  end

  #: (value, i32) -> value
  def zr_capi_load(path, wrap)
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(path))
    Machine.store64(args, 8, Machine.word(zr_bool(Machine.sword(wrap) != 0)))
    zr_send(zr_global(G_MAIN), Machine.id(:load), 2, args)
  end

  # ruby_script: `$0 = name`.
  #: (ptr) -> void
  def ruby_script(name)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_gvar_set(Machine.id(:$0), zr_str_new(name, zr_cstr_len(name))))
  end

  # rb_backtrace: the backtrace of the running method on standard error,
  # as ruby prints it (Kernel.c_backtrace).
  #: () -> void
  def rb_backtrace
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:c_backtrace), 0, Machine.ptr(0)))
  end
end
