module Zr::Kern
  # Boot and the C entry point. The compiler supplies `zr_prelude` (the
  # toplevels of the core library) and `zr_toplevel` (the program's
  # toplevel).

  #: (word, word, value) -> value
  def zr_boot_class(g, name, sup)
    c = zr_class_boot(sup)
    zr_set_global(g, c)
    c
  end

  #: (word, word) -> void
  def zr_boot_name(g, name)
    k = zr_global(g)
    RClass[k].name = zr_class_name_str(zr_usascii_str_new(zr_symbol_name_ptr(name), zr_symbol_name_len(name)))
    zr_const_set(zr_global(G_OBJECT), name, k)
  end

  # The methods that Method and UnboundMethod share.
  #: (value) -> void
  def zr_boot_method_class(klass)
    zr_builtin(klass, Machine.id(:arity), Machine.addr(:zr_method_arity), 0)
    zr_builtin(klass, Machine.id(:parameters), Machine.addr(:zr_method_parameters), 0)
    zr_builtin(klass, Machine.id(:owner), Machine.addr(:zr_method_owner_m), 0)
    zr_builtin(klass, Machine.id(:name), Machine.addr(:zr_method_name), 0)
    zr_builtin(klass, Machine.id(:original_name), Machine.addr(:zr_method_original_name), 0)
    zr_builtin(klass, Machine.id(:source_location), Machine.addr(:zr_method_source_location), 0)
    zr_builtin(klass, Machine.id(:inspect), Machine.addr(:zr_method_inspect), 0)
    zr_builtin(klass, Machine.id(:to_s), Machine.addr(:zr_method_inspect), 0)
    zr_builtin(klass, Machine.id(:==), Machine.addr(:zr_method_eq), 1)
    zr_builtin(klass, Machine.id(:eql?), Machine.addr(:zr_method_eq), 1)
    zr_builtin(klass, Machine.id(:hash), Machine.addr(:zr_method_hash), 0)
  end

  # The size of the stack that the program runs on by default, as a
  # fiber's. Ruby frames are machine frames, and one with many locals,
  # blocks and kernel calls takes some KiB, so the stack has room for at
  # least the depth that ruby's VM stack gives.
  MAIN_STACK_BYTES = 67108864
  # ruby's default VM stack (RUBY_THREAD_VM_STACK_SIZE), which
  # MAIN_STACK_BYTES matches, and the least size that ruby takes.
  VM_STACK_BYTES = 1048576
  VM_STACK_LEAST = 16384
  # The smallest stack that leaves room for the runtime's boot, and the
  # largest that zr maps.
  MAIN_STACK_FLOOR = 4194304
  MAIN_STACK_CEILING = 4294967296

  # The size of the program's stack: MAIN_STACK_BYTES scaled by
  # RUBY_THREAD_VM_STACK_SIZE against ruby's default, so a program recurses
  # about as deep as ruby lets it. The value reads as atol reads its
  # digits, is at least VM_STACK_LEAST and is rounded up to a page, as
  # vm_default_params_setup does.
  #: () -> word
  def zr_main_stack_bytes
    text = Libc.getenv(Machine.bytes("RUBY_THREAD_VM_STACK_SIZE\0"))
    if text == 0
      return MAIN_STACK_BYTES
    end
    size = 0
    i = 0
    while i < 12 && Machine.u8(Machine.load8(text + i, 0)) >= 48 && Machine.u8(Machine.load8(text + i, 0)) <= 57
      size = (size * 10) + Machine.u8(Machine.load8(text + i, 0)) - 48
      i += 1
    end
    if size < VM_STACK_LEAST
      size = VM_STACK_LEAST
    end
    size = (size + 4095) / 4096 * 4096
    bytes = MAIN_STACK_BYTES / VM_STACK_BYTES * size
    if bytes < MAIN_STACK_FLOOR
      return MAIN_STACK_FLOOR
    end
    bytes > MAIN_STACK_CEILING ? MAIN_STACK_CEILING : bytes
  end

  # The program's own stack, after it is mapped: its lowest address, then
  # the arguments and the return value of the entry, then its size.
  #: () -> ptr
  def zr_program_stack_cell
    Machine.static(:program_stack, 32)
  end

  # The contexts that the switch onto the program's stack and back saves.
  #: () -> ptr
  def zr_process_context
    Machine.static(:process_context, CONTEXT_BYTES)
  end

  #: () -> ptr
  def zr_program_context
    Machine.static(:program_context, CONTEXT_BYTES)
  end

  # Runs zr_main on the program's stack, then switches back to the
  # process's stack with its return value.
  #: () -> void
  def zr_own_stack_start
    cell = zr_program_stack_cell()
    r = zr_main(Machine.i32(Machine.load64(cell, 8)), Machine.ptr(Machine.load64(cell, 16)))
    Machine.store64(cell, 8, Machine.u32(r))
    zr_switch(zr_program_context(), zr_process_context())
  end

  # Runs the program on a stack of zr_main_stack_bytes that zr maps, as it
  # maps a fiber's. The process keeps the stack that the system gave it,
  # so the program can change RLIMIT_STACK, which darwin refuses to a
  # binary that sets its own main stack size. If zr cannot map the
  # stack, the program runs on the process's stack.
  #: (i32, ptr) -> i32
  def zr_main_on_own_stack(argc, argv)
    bytes = zr_main_stack_bytes()
    stack = zr_os_stack_map(bytes)
    if stack == 0
      return zr_main(argc, argv)
    end
    cell = zr_program_stack_cell()
    Machine.store64(cell, 0, Machine.word(stack))
    Machine.store64(cell, 8, Machine.u32(argc))
    Machine.store64(cell, 16, Machine.word(argv))
    Machine.store64(cell, 24, bytes)
    zr_arch_context_start(zr_program_context(), Machine.addr(:zr_own_stack_start), Machine.word(stack) + bytes)
    zr_switch(zr_process_context(), zr_program_context())
    Machine.i32(Machine.load64(cell, 8))
  end

  # The lowest address of the program's own stack, or 0 when it runs on
  # the process's stack.
  #: () -> word
  def zr_program_stack_low
    Machine.load64(zr_program_stack_cell(), 0)
  end

  # The address immediately after the top of the program's own stack, or
  # 0 when it runs on the process's stack.
  #: () -> word
  def zr_program_stack_high
    cell = zr_program_stack_cell()
    low = Machine.load64(cell, 0)
    low == 0 ? 0 : low + Machine.load64(cell, 24)
  end

  # The machine stack ends at this margin for Ruby frames. The margin above
  # the thread's guard page keeps space for the kernel's own frames and
  # the error report. A limit of zero, as under wasm, never fails.
  STACK_MARGIN = 262144

  # The stack limit of the main task: the margin above the low end of the
  # OS stack, or zero if the OS does not give the low end.
  #: () -> ptr
  def zr_main_stack_limit
    low = zr_os_stack_low()
    if low == 0
      return Machine.ptr(0)
    end
    Machine.ptr(low + STACK_MARGIN)
  end

  #: () -> void
  def zr_boot
    zr_heap_init()
    zr_mcache_init()
    Machine.store64(zr_current_task_slot(), 0, Machine.word(Machine.static(:task, Task.size)))
    zr_task_init(zr_task(), zr_main_stack_limit())
    zr_hash_seed_init()
    # The four classes that form a cycle come first, with no class. Then
    # each one gets Class as its class. Names come after String exists.
    zr_boot_class(G_BASIC_OBJECT, Machine.id(:BasicObject), Machine.value(QNIL))
    zr_boot_class(G_OBJECT, Machine.id(:Object), zr_global(G_BASIC_OBJECT))
    zr_boot_class(G_MODULE, Machine.id(:Module), zr_global(G_OBJECT))
    zr_boot_class(G_CLASS, Machine.id(:Class), zr_global(G_MODULE))
    i = G_BASIC_OBJECT
    while i <= G_CLASS
      RBasic[zr_global(i)].klass = zr_global(G_CLASS)
      i += 1
    end
    zr_boot_class(G_NUMERIC, Machine.id(:Numeric), zr_global(G_OBJECT))
    zr_boot_class(G_INTEGER, Machine.id(:Integer), zr_global(G_NUMERIC))
    zr_boot_class(G_FLOAT, Machine.id(:Float), zr_global(G_NUMERIC))
    zr_boot_class(G_STRING, Machine.id(:String), zr_global(G_OBJECT))
    zr_boot_class(G_FIBER, Machine.id(:Fiber), zr_global(G_OBJECT))
    zr_boot_class(G_REGEXP, Machine.id(:Regexp), zr_global(G_OBJECT))
    zr_boot_class(G_SYMBOL, Machine.id(:Symbol), zr_global(G_OBJECT))
    zr_boot_class(G_NIL, Machine.id(:NilClass), zr_global(G_OBJECT))
    zr_boot_class(G_TRUE, Machine.id(:TrueClass), zr_global(G_OBJECT))
    zr_boot_class(G_FALSE, Machine.id(:FalseClass), zr_global(G_OBJECT))
    zr_boot_class(G_EXCEPTION, Machine.id(:Exception), zr_global(G_OBJECT))
    zr_boot_class(G_FATAL, Machine.id(:fatal), zr_global(G_EXCEPTION))
    zr_boot_class(G_STANDARD_ERROR, Machine.id(:StandardError), zr_global(G_EXCEPTION))
    zr_boot_class(G_ARGUMENT_ERROR, Machine.id(:ArgumentError), zr_global(G_STANDARD_ERROR))
    zr_boot_class(G_NAME_ERROR, Machine.id(:NameError), zr_global(G_STANDARD_ERROR))
    zr_boot_class(G_NO_METHOD_ERROR, Machine.id(:NoMethodError), zr_global(G_NAME_ERROR))
    zr_boot_class(G_TYPE_ERROR, Machine.id(:TypeError), zr_global(G_STANDARD_ERROR))
    zr_boot_class(G_ZERO_DIVISION_ERROR, Machine.id(:ZeroDivisionError), zr_global(G_STANDARD_ERROR))
    zr_boot_class(G_RUNTIME_ERROR, Machine.id(:RuntimeError), zr_global(G_STANDARD_ERROR))
    zr_boot_class(G_INDEX_ERROR, Machine.id(:IndexError), zr_global(G_STANDARD_ERROR))
    zr_boot_class(G_ARRAY, Machine.id(:Array), zr_global(G_OBJECT))
    zr_boot_class(G_FROZEN_ERROR, Machine.id(:FrozenError), zr_global(G_RUNTIME_ERROR))
    zr_boot_class(G_LOCAL_JUMP_ERROR, Machine.id(:LocalJumpError), zr_global(G_STANDARD_ERROR))
    zr_boot_class(G_PROC, Machine.id(:Proc), zr_global(G_OBJECT))
    zr_boot_class(G_HASH, Machine.id(:Hash), zr_global(G_OBJECT))
    zr_boot_class(G_METHOD, Machine.id(:Method), zr_global(G_OBJECT))
    zr_boot_class(G_UNBOUND_METHOD, Machine.id(:UnboundMethod), zr_global(G_OBJECT))
    zr_boot_class(G_RANGE, Machine.id(:Range), zr_global(G_OBJECT))
    zr_boot_class(G_KEY_ERROR, Machine.id(:KeyError), zr_global(G_INDEX_ERROR))
    zr_boot_class(G_SYSTEM_STACK_ERROR, Machine.id(:SystemStackError), zr_global(G_EXCEPTION))
    zr_boot_class(G_REFINEMENT, Machine.id(:Refinement), zr_global(G_MODULE))
    zr_set_global(G_KERNEL, zr_module_new())
    zr_boot_name(G_KERNEL, Machine.id(:Kernel))
    zr_include_module(zr_global(G_OBJECT), zr_global(G_KERNEL))
    zr_boot_name(G_BASIC_OBJECT, Machine.id(:BasicObject))
    zr_boot_name(G_OBJECT, Machine.id(:Object))
    zr_boot_name(G_MODULE, Machine.id(:Module))
    zr_boot_name(G_CLASS, Machine.id(:Class))
    zr_boot_name(G_INTEGER, Machine.id(:Integer))
    zr_boot_name(G_STRING, Machine.id(:String))
    zr_boot_name(G_FIBER, Machine.id(:Fiber))
    zr_boot_name(G_SYMBOL, Machine.id(:Symbol))
    zr_boot_name(G_NIL, Machine.id(:NilClass))
    zr_boot_name(G_TRUE, Machine.id(:TrueClass))
    zr_boot_name(G_FALSE, Machine.id(:FalseClass))
    zr_boot_name(G_EXCEPTION, Machine.id(:Exception))
    zr_boot_name(G_STANDARD_ERROR, Machine.id(:StandardError))
    zr_boot_name(G_ARGUMENT_ERROR, Machine.id(:ArgumentError))
    zr_boot_name(G_NAME_ERROR, Machine.id(:NameError))
    zr_boot_name(G_NO_METHOD_ERROR, Machine.id(:NoMethodError))
    zr_boot_name(G_TYPE_ERROR, Machine.id(:TypeError))
    zr_boot_name(G_ZERO_DIVISION_ERROR, Machine.id(:ZeroDivisionError))
    zr_boot_name(G_RUNTIME_ERROR, Machine.id(:RuntimeError))
    zr_boot_name(G_INDEX_ERROR, Machine.id(:IndexError))
    zr_boot_name(G_ARRAY, Machine.id(:Array))
    zr_boot_name(G_FROZEN_ERROR, Machine.id(:FrozenError))
    zr_boot_name(G_LOCAL_JUMP_ERROR, Machine.id(:LocalJumpError))
    zr_boot_name(G_PROC, Machine.id(:Proc))
    zr_boot_name(G_HASH, Machine.id(:Hash))
    zr_boot_name(G_METHOD, Machine.id(:Method))
    zr_boot_name(G_UNBOUND_METHOD, Machine.id(:UnboundMethod))
    zr_boot_name(G_RANGE, Machine.id(:Range))
    zr_boot_name(G_REFINEMENT, Machine.id(:Refinement))
    zr_boot_name(G_NUMERIC, Machine.id(:Numeric))
    zr_boot_name(G_FLOAT, Machine.id(:Float))
    zr_boot_name(G_REGEXP, Machine.id(:Regexp))
    RClass[zr_global(G_FATAL)].name = zr_class_name_str(zr_usascii_str_new(Machine.bytes("fatal"), 5))
    zr_boot_name(G_KEY_ERROR, Machine.id(:KeyError))
    zr_boot_name(G_SYSTEM_STACK_ERROR, Machine.id(:SystemStackError))
    zr_alloc_table()
    # Each boot class gets its metaclass, so that a singleton method on an
    # ancestor is visible to it.
    i = G_BASIC_OBJECT
    while i < G_COUNT
      k = zr_global(i)
      if k != QNIL && !zr_special_p(k) && zr_type(k) == T_CLASS
        zr_singleton_class(k)
      end
      i += 1
    end
    zr_set_global(G_MAIN, zr_obj_alloc(zr_global(G_OBJECT)))
    zr_set_global(G_TOP_CREF, zr_cref_push(zr_global(G_OBJECT), Machine.value(QNIL)))
    # A top-level def is private, as in CRuby's toplevel scope.
    RCref[zr_global(G_TOP_CREF)].vis = VIS_PRIVATE
    # Kernel gets the methods of CRuby's Kernel. BasicObject gets its small
    # set of methods.
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:puts), Machine.addr(:zr_puts), 0 - 1)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:raise), Machine.addr(:zr_kernel_raise), 0 - 1)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:proc), Machine.addr(:zr_kernel_proc), 0)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:lambda), Machine.addr(:zr_kernel_lambda), 0)
    zr_builtin(zr_singleton_class(zr_global(G_PROC)), Machine.id(:new), Machine.addr(:zr_proc_s_new), 0 - 1)
    zr_define_method(zr_global(G_PROC), Machine.id(:call), Machine.addr(:zr_proc_call), 0 - 1, KIND_FRAMELESS, 0, Machine.value(QNIL))
    zr_define_method(zr_global(G_PROC), Machine.id(:[]), Machine.addr(:zr_proc_call), 0 - 1, KIND_FRAMELESS, 0, Machine.value(QNIL))
    zr_define_method(zr_global(G_PROC), Machine.id(:yield), Machine.addr(:zr_proc_call), 0 - 1, KIND_FRAMELESS, 0, Machine.value(QNIL))
    zr_builtin(zr_global(G_PROC), Machine.id(:lambda?), Machine.addr(:zr_proc_lambda_p), 0)
    zr_builtin(zr_global(G_PROC), Machine.id(:inspect), Machine.addr(:zr_proc_inspect), 0)
    zr_builtin(zr_global(G_PROC), Machine.id(:to_s), Machine.addr(:zr_proc_inspect), 0)
    zr_builtin(zr_global(G_PROC), Machine.id(:arity), Machine.addr(:zr_proc_arity), 0)
    zr_builtin(zr_global(G_PROC), Machine.id(:==), Machine.addr(:zr_proc_eq), 1)
    zr_builtin(zr_global(G_PROC), Machine.id(:eql?), Machine.addr(:zr_proc_eq), 1)
    zr_builtin(zr_global(G_PROC), Machine.id(:hash), Machine.addr(:zr_proc_hash), 0)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:p), Machine.addr(:zr_p), 0 - 1)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:print), Machine.addr(:zr_print), 0 - 1)
    # `send` and `__send__` add no backtrace frame, as in CRuby.
    zr_define_method(zr_global(G_KERNEL), Machine.id(:send), Machine.addr(:zr_obj_send), 0 - 1, KIND_FRAMELESS, 0, Machine.value(QNIL))
    zr_builtin(zr_global(G_KERNEL), Machine.id(:eql?), Machine.addr(:zr_obj_eql_p), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:hash), Machine.addr(:zr_obj_hash), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:hash), Machine.addr(:zr_str_hash), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:eql?), Machine.addr(:zr_str_eq), 1)
    zr_define_method(zr_global(G_BASIC_OBJECT), Machine.id(:__send__), Machine.addr(:zr_obj_send), 0 - 1, KIND_FRAMELESS, 0, Machine.value(QNIL))
    zr_builtin(zr_global(G_KERNEL), Machine.id(:public_send), Machine.addr(:zr_obj_public_send), 0 - 1)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:private), Machine.addr(:zr_mod_private), 0 - 1)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:public), Machine.addr(:zr_mod_public), 0 - 1)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:protected), Machine.addr(:zr_mod_protected), 0 - 1)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:module_function), Machine.addr(:zr_mod_module_function), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:private_class_method), Machine.addr(:zr_mod_private_class_method), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:public_class_method), Machine.addr(:zr_mod_public_class_method), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:instance_methods), Machine.addr(:zr_mod_instance_methods), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:public_instance_methods), Machine.addr(:zr_mod_public_instance_methods), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:private_instance_methods), Machine.addr(:zr_mod_private_instance_methods), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:protected_instance_methods), Machine.addr(:zr_mod_protected_instance_methods), 0 - 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:<=>), Machine.addr(:zr_str_cmp), 1)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:block_given?), Machine.addr(:zr_block_given_p), 0)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:iterator?), Machine.addr(:zr_block_given_p), 0)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:times), Machine.addr(:zr_int_times), 0)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:upto), Machine.addr(:zr_int_upto), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:downto), Machine.addr(:zr_int_downto), 1)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:each), Machine.addr(:zr_ary_each), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:each_index), Machine.addr(:zr_ary_each_index), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:map), Machine.addr(:zr_ary_map), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:collect), Machine.addr(:zr_ary_collect), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:select), Machine.addr(:zr_ary_select), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:filter), Machine.addr(:zr_ary_select), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:reject), Machine.addr(:zr_ary_reject), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:sort), Machine.addr(:zr_ary_sort), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:sort!), Machine.addr(:zr_ary_sort_bang), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:to_s), Machine.addr(:zr_obj_to_s), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:inspect), Machine.addr(:zr_obj_inspect), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:class), Machine.addr(:zr_obj_class), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:singleton_class), Machine.addr(:zr_obj_singleton_class), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:extend), Machine.addr(:zr_obj_extend), 0 - 1)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:extend_object), Machine.addr(:zr_mod_extend_object), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:method), Machine.addr(:zr_obj_method), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:instance_method), Machine.addr(:zr_mod_instance_method), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:public_method), Machine.addr(:zr_obj_public_method), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:public_instance_method), Machine.addr(:zr_mod_public_instance_method), 1)
    zr_builtin_private(zr_global(G_CLASS), Machine.id(:initialize), Machine.addr(:zr_class_initialize), 0 - 1)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:initialize), Machine.addr(:zr_module_initialize), 0)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:prepend_features), Machine.addr(:zr_mod_prepend_features), 1)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:append_features), Machine.addr(:zr_mod_append_features), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:method_defined?), Machine.addr(:zr_mod_method_defined), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:public_method_defined?), Machine.addr(:zr_mod_public_method_defined), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:private_method_defined?), Machine.addr(:zr_mod_private_method_defined), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:protected_method_defined?), Machine.addr(:zr_mod_protected_method_defined), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:autoload?), Machine.addr(:zr_mod_autoload_p), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:const_set), Machine.addr(:zr_mod_const_set), 2)
    zr_builtin_private(zr_global(G_MODULE), Machine.id(:remove_const), Machine.addr(:zr_mod_remove_const), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:constants), Machine.addr(:zr_mod_constants), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:class_eval), Machine.addr(:zr_mod_class_eval), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:module_eval), Machine.addr(:zr_mod_class_eval), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:class_exec), Machine.addr(:zr_mod_class_exec), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:module_exec), Machine.addr(:zr_mod_class_exec), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:define_method), Machine.addr(:zr_mod_define_method), 0 - 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:define_singleton_method), Machine.addr(:zr_obj_define_singleton_method), 0 - 1)
    zr_builtin(zr_global(G_BASIC_OBJECT), Machine.id(:instance_eval), Machine.addr(:zr_obj_instance_eval), 0 - 1)
    zr_builtin(zr_global(G_BASIC_OBJECT), Machine.id(:instance_exec), Machine.addr(:zr_obj_instance_exec), 0 - 1)
    zr_boot_method_class(zr_global(G_METHOD))
    zr_boot_method_class(zr_global(G_UNBOUND_METHOD))
    zr_builtin(zr_global(G_METHOD), Machine.id(:call), Machine.addr(:zr_method_call), 0 - 1)
    zr_builtin(zr_global(G_METHOD), Machine.id(:[]), Machine.addr(:zr_method_call), 0 - 1)
    zr_builtin(zr_global(G_METHOD), Machine.id(:===), Machine.addr(:zr_method_call), 0 - 1)
    zr_builtin(zr_global(G_METHOD), Machine.id(:to_proc), Machine.addr(:zr_method_to_proc), 0)
    zr_builtin(zr_global(G_METHOD), Machine.id(:receiver), Machine.addr(:zr_method_receiver), 0)
    zr_builtin(zr_global(G_METHOD), Machine.id(:unbind), Machine.addr(:zr_method_unbind), 0)
    zr_builtin(zr_global(G_UNBOUND_METHOD), Machine.id(:bind), Machine.addr(:zr_method_bind), 1)
    zr_builtin(zr_global(G_UNBOUND_METHOD), Machine.id(:bind_call), Machine.addr(:zr_method_bind_call), 0 - 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:singleton_methods), Machine.addr(:zr_obj_singleton_methods), 0 - 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:methods), Machine.addr(:zr_obj_methods), 0 - 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:public_methods), Machine.addr(:zr_obj_public_methods), 0 - 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:private_methods), Machine.addr(:zr_obj_private_methods), 0 - 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:protected_methods), Machine.addr(:zr_obj_protected_methods), 0 - 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:instance_variables), Machine.addr(:zr_obj_instance_variables), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:object_id), Machine.addr(:zr_obj_object_id), 0)
    zr_alias(zr_global(G_KERNEL), Machine.id(:fail), Machine.id(:raise))
    zr_builtin(zr_global(G_BASIC_OBJECT), Machine.id(:__id__), Machine.addr(:zr_obj_object_id), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:instance_variable_get), Machine.addr(:zr_obj_instance_variable_get), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:instance_variable_set), Machine.addr(:zr_obj_instance_variable_set), 2)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:instance_variable_defined?), Machine.addr(:zr_obj_instance_variable_defined), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:class_variables), Machine.addr(:zr_mod_class_variables), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:class_variable_get), Machine.addr(:zr_mod_class_variable_get), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:class_variable_set), Machine.addr(:zr_mod_class_variable_set), 2)
    zr_builtin(zr_global(G_MODULE), Machine.id(:class_variable_defined?), Machine.addr(:zr_mod_class_variable_defined), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:is_a?), Machine.addr(:zr_obj_is_a), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:kind_of?), Machine.addr(:zr_obj_is_a), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:instance_of?), Machine.addr(:zr_obj_instance_of), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:nil?), Machine.addr(:zr_obj_nil_p), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:respond_to?), Machine.addr(:zr_obj_respond_to), 0 - 1)
    # Exception has a private method_missing. Thus CRuby gives it its own
    # respond_to?, which returns the same as Kernel's.
    zr_builtin(zr_global(G_EXCEPTION), Machine.id(:respond_to?), Machine.addr(:zr_obj_respond_to), 0 - 1)
    zr_builtin(zr_global(G_BASIC_OBJECT), Machine.id(:initialize), Machine.addr(:zr_obj_initialize), 0)
    zr_builtin_private(zr_global(G_BASIC_OBJECT), Machine.id(:method_missing), Machine.addr(:zr_obj_method_missing), 0 - 1)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:respond_to_missing?), Machine.addr(:zr_obj_respond_to_missing), 2)
    zr_builtin(zr_global(G_BASIC_OBJECT), Machine.id(:==), Machine.addr(:zr_obj_eq), 1)
    zr_builtin(zr_global(G_BASIC_OBJECT), Machine.id(:equal?), Machine.addr(:zr_obj_eq), 1)
    zr_builtin(zr_global(G_BASIC_OBJECT), Machine.id(:!=), Machine.addr(:zr_obj_ne), 1)
    zr_builtin(zr_global(G_BASIC_OBJECT), Machine.id(:!), Machine.addr(:zr_obj_not), 0)
    zr_builtin(zr_global(G_CLASS), Machine.id(:allocate), Machine.addr(:zr_class_allocate_m), 0)
    # `Class.allocate` is defined on Class itself. It makes a class that
    # is not set up yet.
    zr_builtin(zr_singleton_class(zr_global(G_CLASS)), Machine.id(:allocate), Machine.addr(:zr_class_allocate_m), 0)
    zr_builtin(zr_global(G_CLASS), Machine.id(:new), Machine.addr(:zr_class_new_instance), 0 - 1)
    zr_builtin(zr_singleton_class(zr_global(G_ARRAY)), Machine.id(:new), Machine.addr(:zr_class_s_new), 0 - 1)
    zr_builtin(zr_singleton_class(zr_global(G_STRING)), Machine.id(:new), Machine.addr(:zr_class_s_new), 0 - 1)
    zr_builtin(zr_global(G_CLASS), Machine.id(:superclass), Machine.addr(:zr_class_superclass), 0)
    zr_builtin(zr_global(G_MODULE), Machine.id(:name), Machine.addr(:zr_class_name), 0)
    zr_builtin(zr_global(G_MODULE), Machine.id(:include?), Machine.addr(:zr_mod_include_p), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:alias_method), Machine.addr(:zr_mod_alias_method), 2)
    zr_builtin(zr_global(G_MODULE), Machine.id(:undef_method), Machine.addr(:zr_mod_undef_method), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:ancestors), Machine.addr(:zr_mod_ancestors), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:initialize), Machine.addr(:zr_str_initialize), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:===), Machine.addr(:zr_mod_eqq), 1)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:===), Machine.addr(:zr_obj_eqq), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:to_s), Machine.addr(:zr_class_to_s), 0)
    zr_builtin(zr_global(G_MODULE), Machine.id(:inspect), Machine.addr(:zr_class_to_s), 0)
    zr_builtin(zr_global(G_MODULE), Machine.id(:attr_reader), Machine.addr(:zr_mod_attr_reader), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:attr_writer), Machine.addr(:zr_mod_attr_writer), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:attr_accessor), Machine.addr(:zr_mod_attr_accessor), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:attr), Machine.addr(:zr_mod_attr), 0 - 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:to_s), Machine.addr(:zr_int_to_s), 0 - 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:+), Machine.addr(:zr_int_plus), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:-), Machine.addr(:zr_int_minus), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:*), Machine.addr(:zr_int_mul), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:/), Machine.addr(:zr_int_div), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:%), Machine.addr(:zr_int_mod), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:&), Machine.addr(:zr_int_and), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:|), Machine.addr(:zr_int_or), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:^), Machine.addr(:zr_int_xor), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:~), Machine.addr(:zr_int_not), 0)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:<<), Machine.addr(:zr_int_lshift), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:>>), Machine.addr(:zr_int_rshift), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:<), Machine.addr(:zr_int_lt), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:<=), Machine.addr(:zr_int_le), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:>), Machine.addr(:zr_int_gt), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:>=), Machine.addr(:zr_int_ge), 1)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:==), Machine.addr(:zr_int_eq), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:to_s), Machine.addr(:zr_str_to_s), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:to_str), Machine.addr(:zr_str_to_s), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:inspect), Machine.addr(:zr_str_inspect), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:+), Machine.addr(:zr_str_plus), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:*), Machine.addr(:zr_str_times), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:<<), Machine.addr(:zr_str_concat), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:concat), Machine.addr(:zr_str_concat_m), 0 - 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:==), Machine.addr(:zr_str_equal), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:===), Machine.addr(:zr_str_equal), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:eql?), Machine.addr(:zr_str_eq), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:length), Machine.addr(:zr_str_length), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:size), Machine.addr(:zr_str_length), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:upcase), Machine.addr(:zr_str_upcase), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:downcase), Machine.addr(:zr_str_downcase), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:capitalize), Machine.addr(:zr_str_capitalize), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:reverse), Machine.addr(:zr_str_reverse), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:include?), Machine.addr(:zr_str_include_p), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:index), Machine.addr(:zr_str_index), 1)
    zr_builtin(zr_global(G_STRING), Machine.id(:empty?), Machine.addr(:zr_str_empty_p), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:to_sym), Machine.addr(:zr_str_to_sym), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:intern), Machine.addr(:zr_str_to_sym), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:+@), Machine.addr(:zr_str_uplus), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:-@), Machine.addr(:zr_str_uminus), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:freeze), Machine.addr(:zr_obj_freeze), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:frozen?), Machine.addr(:zr_obj_frozen_p), 0)
    zr_builtin(zr_global(G_SYMBOL), Machine.id(:to_s), Machine.addr(:zr_sym_to_s), 0)
    zr_builtin(zr_global(G_SYMBOL), Machine.id(:<=>), Machine.addr(:zr_sym_cmp), 1)
    # Symbol's own `==` compares identity, as sym_equal does. Comparable's
    # `==` would call `<=>`.
    zr_builtin(zr_global(G_SYMBOL), Machine.id(:==), Machine.addr(:zr_obj_eq), 1)
    zr_builtin(zr_global(G_SYMBOL), Machine.id(:to_proc), Machine.addr(:zr_sym_to_proc_m), 0)
    zr_builtin(zr_global(G_SYMBOL), Machine.id(:inspect), Machine.addr(:zr_sym_inspect), 0)
    zr_builtin(zr_global(G_NIL), Machine.id(:to_s), Machine.addr(:zr_nil_to_s), 0)
    zr_builtin(zr_global(G_NIL), Machine.id(:inspect), Machine.addr(:zr_nil_inspect), 0)
    # CRuby defines these method entries on each class, with the same
    # function as the Kernel entry. Thus the class owns them.
    zr_builtin(zr_global(G_NIL), Machine.id(:===), Machine.addr(:zr_obj_eqq), 1)
    zr_builtin(zr_global(G_TRUE), Machine.id(:===), Machine.addr(:zr_obj_eqq), 1)
    zr_builtin(zr_global(G_FALSE), Machine.id(:===), Machine.addr(:zr_obj_eqq), 1)
    # symbol.c's sym_equal: `===` is identity, as `==` is.
    zr_builtin(zr_global(G_SYMBOL), Machine.id(:===), Machine.addr(:zr_obj_eq), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:==), Machine.addr(:zr_obj_eq), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:freeze), Machine.addr(:zr_obj_freeze), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:freeze), Machine.addr(:zr_obj_freeze), 0)
    zr_builtin(zr_global(G_STRING), Machine.id(:dup), Machine.addr(:zr_obj_dup), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:freeze), Machine.addr(:zr_obj_freeze), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:freeze), Machine.addr(:zr_obj_freeze), 0)
    zr_builtin(zr_global(G_PROC), Machine.id(:dup), Machine.addr(:zr_obj_dup), 0)
    zr_builtin(zr_global(G_PROC), Machine.id(:clone), Machine.addr(:zr_obj_clone_m), 0)
    zr_builtin(zr_global(G_METHOD), Machine.id(:dup), Machine.addr(:zr_obj_dup), 0)
    zr_builtin(zr_global(G_METHOD), Machine.id(:clone), Machine.addr(:zr_obj_clone_m), 0)
    zr_builtin(zr_global(G_UNBOUND_METHOD), Machine.id(:dup), Machine.addr(:zr_obj_dup), 0)
    zr_builtin(zr_global(G_UNBOUND_METHOD), Machine.id(:clone), Machine.addr(:zr_obj_clone_m), 0)
    zr_builtin(zr_global(G_TRUE), Machine.id(:to_s), Machine.addr(:zr_true_to_s), 0)
    zr_builtin(zr_global(G_TRUE), Machine.id(:inspect), Machine.addr(:zr_true_inspect), 0)
    zr_builtin(zr_global(G_FALSE), Machine.id(:to_s), Machine.addr(:zr_false_to_s), 0)
    zr_builtin(zr_global(G_FALSE), Machine.id(:inspect), Machine.addr(:zr_false_inspect), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:[]), Machine.addr(:zr_ary_aref), 0 - 1)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:<<), Machine.addr(:zr_ary_push_m), 1)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:push), Machine.addr(:zr_ary_push_m), 0 - 1)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:pop), Machine.addr(:zr_ary_pop), 0 - 1)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:shift), Machine.addr(:zr_ary_shift), 0 - 1)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:unshift), Machine.addr(:zr_ary_unshift_m), 0 - 1)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:prepend), Machine.addr(:zr_ary_unshift_m), 0 - 1)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:reverse!), Machine.addr(:zr_ary_reverse_bang), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:size), Machine.addr(:zr_ary_length), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:length), Machine.addr(:zr_ary_length), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:empty?), Machine.addr(:zr_ary_empty_p), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:first), Machine.addr(:zr_ary_first), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:last), Machine.addr(:zr_ary_last), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:inspect), Machine.addr(:zr_ary_inspect), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:to_s), Machine.addr(:zr_ary_inspect), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:==), Machine.addr(:zr_ary_eq), 1)
    zr_builtin(zr_global(G_EXCEPTION), Machine.id(:initialize), Machine.addr(:zr_exc_initialize), 0 - 1)
    zr_builtin(zr_global(G_EXCEPTION), Machine.id(:inspect), Machine.addr(:zr_exc_inspect), 0)
    zr_builtin(zr_global(G_EXCEPTION), Machine.id(:backtrace), Machine.addr(:zr_exc_backtrace), 0)
    zr_builtin(zr_global(G_EXCEPTION), Machine.id(:set_backtrace), Machine.addr(:zr_exc_set_backtrace), 1)
    zr_builtin(zr_global(G_EXCEPTION), Machine.id(:cause), Machine.addr(:zr_exc_cause), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:dup), Machine.addr(:zr_obj_dup), 0)
    zr_builtin(zr_global(G_ARRAY), Machine.id(:initialize), Machine.addr(:zr_ary_initialize), 0 - 1)
    zr_builtin_private(zr_global(G_ARRAY), Machine.id(:initialize_copy), Machine.addr(:zr_ary_initialize_copy), 1)
    zr_builtin_private(zr_global(G_HASH), Machine.id(:initialize_copy), Machine.addr(:zr_hash_initialize_copy), 1)
    zr_builtin_private(zr_global(G_STRING), Machine.id(:initialize_copy), Machine.addr(:zr_str_initialize_copy), 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:[]), Machine.addr(:zr_hash_aref), 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:[]=), Machine.addr(:zr_hash_aset), 2)
    zr_builtin(zr_global(G_HASH), Machine.id(:fetch), Machine.addr(:zr_hash_fetch), 0 - 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:key?), Machine.addr(:zr_hash_key_p), 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:has_key?), Machine.addr(:zr_hash_key_p), 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:include?), Machine.addr(:zr_hash_key_p), 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:member?), Machine.addr(:zr_hash_key_p), 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:delete), Machine.addr(:zr_hash_delete), 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:size), Machine.addr(:zr_hash_size), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:length), Machine.addr(:zr_hash_size), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:empty?), Machine.addr(:zr_hash_empty_p), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:keys), Machine.addr(:zr_hash_keys), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:values), Machine.addr(:zr_hash_values), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:each), Machine.addr(:zr_hash_each), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:each_pair), Machine.addr(:zr_hash_each), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:to_a), Machine.addr(:zr_hash_to_a), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:inspect), Machine.addr(:zr_hash_inspect), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:to_s), Machine.addr(:zr_hash_inspect), 0)
    zr_builtin(zr_global(G_HASH), Machine.id(:==), Machine.addr(:zr_hash_eq), 1)
    zr_builtin(zr_global(G_HASH), Machine.id(:default), Machine.addr(:zr_hash_default_m), 0)
    zr_builtin(zr_global(G_METHOD), Machine.id(:super_method), Machine.addr(:zr_method_super_method), 0)
    zr_builtin(zr_global(G_UNBOUND_METHOD), Machine.id(:super_method), Machine.addr(:zr_method_super_method), 0)
    zr_builtin(zr_global(G_MODULE), Machine.id(:included_modules), Machine.addr(:zr_mod_included_modules), 0)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:__method__), Machine.addr(:zr_kernel_method_name), 0)
    zr_builtin(zr_global(G_PROC), Machine.id(:source_location), Machine.addr(:zr_proc_source_location), 0)
    zr_builtin(zr_global(G_MODULE), Machine.id(:remove_method), Machine.addr(:zr_mod_remove_method), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:refine), Machine.addr(:zr_mod_refine), 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:private_constant), Machine.addr(:zr_mod_private_constant), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:public_constant), Machine.addr(:zr_mod_public_constant), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:deprecate_constant), Machine.addr(:zr_mod_deprecate_constant), 0 - 1)
    zr_builtin(zr_global(G_MODULE), Machine.id(:remove_class_variable), Machine.addr(:zr_mod_remove_class_variable), 1)
    zr_builtin(zr_singleton_class(zr_global(G_MODULE)), Machine.id(:nesting), Machine.addr(:zr_mod_nesting), 0)
    zr_builtin(zr_singleton_class(zr_global(G_MODULE)), Machine.id(:constants), Machine.addr(:zr_mod_s_constants), 0 - 1)
    zr_builtin(zr_singleton_class(zr_global(G_MODULE)), Machine.id(:used_modules), Machine.addr(:zr_mod_used_modules), 0)
    zr_builtin(zr_singleton_class(zr_global(G_MODULE)), Machine.id(:used_refinements), Machine.addr(:zr_mod_used_refinements), 0)
    zr_builtin(zr_global(G_MODULE), Machine.id(:undefined_instance_methods), Machine.addr(:zr_mod_undefined_instance_methods), 0)
    zr_builtin(zr_global(G_CLASS), Machine.id(:subclasses), Machine.addr(:zr_class_subclasses), 0)
    zr_builtin(zr_global(G_KERNEL), Machine.id(:remove_instance_variable), Machine.addr(:zr_obj_remove_instance_variable), 1)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:caller), Machine.addr(:zr_kernel_caller), 0 - 1)
    zr_builtin_private(zr_global(G_KERNEL), Machine.id(:__callee__), Machine.addr(:zr_kernel_callee), 0)
    zr_builtin(zr_global(G_MODULE), Machine.id(:singleton_class?), Machine.addr(:zr_mod_singleton_class_p), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:+), Machine.addr(:zr_flo_plus), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:-), Machine.addr(:zr_flo_minus), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:*), Machine.addr(:zr_flo_mul), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:/), Machine.addr(:zr_flo_div), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:%), Machine.addr(:zr_flo_mod), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:modulo), Machine.addr(:zr_flo_mod), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:**), Machine.addr(:zr_flo_pow), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:-@), Machine.addr(:zr_flo_uminus), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:==), Machine.addr(:zr_flo_eq), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:===), Machine.addr(:zr_flo_eq), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:<=>), Machine.addr(:zr_flo_cmp), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:<), Machine.addr(:zr_flo_lt), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:<=), Machine.addr(:zr_flo_le), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:>), Machine.addr(:zr_flo_gt), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:>=), Machine.addr(:zr_flo_ge), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:to_i), Machine.addr(:zr_flo_to_i), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:to_int), Machine.addr(:zr_flo_to_i), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:nan?), Machine.addr(:zr_flo_nan_p), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:next_float), Machine.addr(:zr_flo_next_float), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:prev_float), Machine.addr(:zr_flo_prev_float), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:infinite?), Machine.addr(:zr_flo_infinite_p), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:finite?), Machine.addr(:zr_flo_finite_p), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:abs), Machine.addr(:zr_flo_abs), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:magnitude), Machine.addr(:zr_flo_abs), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:hash), Machine.addr(:zr_flo_hash), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:eql?), Machine.addr(:zr_flo_eql_p), 1)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:to_s), Machine.addr(:zr_flo_to_s), 0)
    zr_builtin(zr_global(G_FLOAT), Machine.id(:inspect), Machine.addr(:zr_flo_to_s), 0)
    zr_builtin(zr_global(G_INTEGER), Machine.id(:to_f), Machine.addr(:zr_int_to_f), 0)
    fiber = zr_singleton_class(zr_global(G_FIBER))
    zr_builtin_hidden(zr_global(G_FIBER), Machine.id(:__make__), Machine.addr(:zr_fiber_make), 0)
    zr_builtin_hidden(fiber, Machine.id(:__yield__), Machine.addr(:zr_fiber_yield), 0 - 1)
    zr_builtin(fiber, Machine.id(:current), Machine.addr(:zr_fiber_current_m), 0)
    zr_builtin_hidden(zr_global(G_FIBER), Machine.id(:__resume__), Machine.addr(:zr_fiber_resume), 0 - 1)
    zr_builtin_hidden(zr_global(G_FIBER), Machine.id(:__transfer__), Machine.addr(:zr_fiber_transfer), 0 - 1)
    zr_builtin(zr_global(G_FIBER), Machine.id(:alive?), Machine.addr(:zr_fiber_alive_p), 0)
    main = zr_singleton_class(zr_global(G_MAIN))
    zr_builtin_private(main, Machine.id(:include), Machine.addr(:zr_main_include), 0 - 1)
    zr_builtin_private(main, Machine.id(:public), Machine.addr(:zr_main_public), 0 - 1)
    zr_builtin_private(main, Machine.id(:private), Machine.addr(:zr_main_private), 0 - 1)
    zr_builtin_private(main, Machine.id(:define_method), Machine.addr(:zr_main_define_method), 0 - 1)
    zr_builtin(main, Machine.id(:to_s), Machine.addr(:zr_main_to_s), 0)
    zr_builtin(main, Machine.id(:inspect), Machine.addr(:zr_main_to_s), 0)
  end

  # The program's entry. The OS layer runs `zr_main` on the stack that
  # Ruby frames need, which is not always the stack the process starts on.
  #: (i32, ptr) -> i32
  def main(argc, argv)
    Machine.gates_enter
    zr_os_main(argc, argv)
  end

  #: (i32, ptr) -> i32
  def zr_main(argc, argv)
    zr_boot()
    zr_args_init(argc, argv)
    r = Libc.zr_prelude()
    if r == QUNDEF
      zr_report(Task[zr_task()].pending)
    end
    # A box sees the shared state as it is here, before the program
    # writes anything of its own. The same snapshot records the operator
    # bodies that the inline fast paths replace.
    zr_box_snapshot()
    zr_runtime_written()
    # The libraries that ruby loads before a program: error_highlight,
    # did_you_mean and syntax_suggest's core extension. The fast paths
    # replace the operators as they are after these libraries load.
    if !zr_gems_off_p()
      r = Libc.zr_gem_prelude()
      if r == QUNDEF
        zr_report(Task[zr_task()].pending)
      end
    end
    zr_gates_snapshot()
    r = Libc.zr_toplevel()
    exc = Machine.value(QUNDEF)
    if r == QUNDEF
      # Each break stops at the call that received its block, or becomes a
      # LocalJumpError before it leaves. A break that gets here is a bug
      # in the runtime. It reports the bug, and does not exit 1 silently.
      if Task[zr_task()].pending_kind == PENDING_BREAK
        zr_bug(Machine.bytes("a break reached the end of the program with no call to leave\n"), 61)
      end
      exc = Task[zr_task()].pending
      Task[zr_task()].pending = Machine.value(QNIL)
    end
    Machine.i32(zr_program_end(exc))
  end
end
