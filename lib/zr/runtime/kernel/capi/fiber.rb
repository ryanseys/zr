module Zr::Kern
  # The C API of Fibers and of the fiber scheduler: each one the Fiber
  # method of its name.

  # rb_fiber_new: a Fiber whose block is the C block function `fn` with
  # the data word `obj` (rb_block_call's form).
  #: (ptr, word) -> value
  def rb_fiber_new(fn, obj)
    Machine.gates_enter
    zr_c_entered()
    body = zr_capi_cblock_new(fn, obj)
    zr_c_result(zr_send_blk(zr_capi_fiber_class(), Machine.id(:new), 0, Machine.ptr(0), body))
  end

  # rb_fiber_current: Fiber.current.
  #: () -> value
  def rb_fiber_current
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_capi_fiber_class(), Machine.id(:current), 0, Machine.ptr(0)))
  end

  # rb_fiber_alive_p: Fiber#alive?.
  #: (value) -> value
  def rb_fiber_alive_p(fiber)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(fiber, Machine.id(:alive?), 0, Machine.ptr(0)))
  end

  # rb_obj_is_fiber: whether `obj` is a Fiber.
  #: (value) -> value
  def rb_obj_is_fiber(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_bool(zr_is_a(obj, zr_capi_fiber_class()))
  end

  # rb_fiber_resume, rb_fiber_transfer and rb_fiber_raise: Fiber#resume,
  # #transfer and #raise with the `argc` arguments at `argv`.
  #: (value, i32, ptr) -> value
  def rb_fiber_resume(fiber, argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(fiber, Machine.id(:resume), Machine.sword(argc), argv))
  end

  #: (value, i32, ptr, i32) -> value
  def rb_fiber_resume_kw(fiber, argc, argv, kw_splat)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_capi_send_maybe_kw(fiber, Machine.id(:resume), Machine.sword(argc), argv, kw_splat))
  end

  #: (value, i32, ptr) -> value
  def rb_fiber_transfer(fiber, argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(fiber, Machine.id(:transfer), Machine.sword(argc), argv))
  end

  #: (value, i32, ptr) -> value
  def rb_fiber_raise(fiber, argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(fiber, Machine.id(:raise), Machine.sword(argc), argv))
  end

  # rb_fiber_yield: Fiber.yield with the `argc` values at `argv`.
  #: (i32, ptr) -> value
  def rb_fiber_yield(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_capi_fiber_class(), Machine.id(:yield), Machine.sword(argc), argv))
  end

  # rb_fiber_scheduler_get and rb_fiber_scheduler_current: the thread's
  # scheduler, and the one that the current fiber uses (nil for a
  # blocking fiber).
  #: () -> value
  def rb_fiber_scheduler_get
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_capi_fiber_class(), Machine.id(:scheduler), 0, Machine.ptr(0)))
  end

  #: () -> value
  def rb_fiber_scheduler_current
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_capi_fiber_class(), Machine.id(:current_scheduler), 0, Machine.ptr(0)))
  end

  # rb_fiber_scheduler_block and rb_fiber_scheduler_unblock: the
  # scheduler's `block(blocker, timeout)` and `unblock(blocker, fiber)`.
  #: (value, value, value) -> value
  def rb_fiber_scheduler_block(scheduler, blocker, timeout)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(blocker))
    Machine.store64(args, 8, Machine.word(timeout))
    zr_c_result(zr_send(scheduler, Machine.id(:block), 2, args))
  end

  #: (value, value, value) -> value
  def rb_fiber_scheduler_unblock(scheduler, blocker, fiber)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(blocker))
    Machine.store64(args, 8, Machine.word(fiber))
    zr_c_result(zr_send(scheduler, Machine.id(:unblock), 2, args))
  end

  #: () -> value
  def zr_capi_fiber_class
    zr_core_class(Machine.id(:Fiber))
  end
end
