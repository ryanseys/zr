module Zr::Kern
  # wasi has no OS threads, so its Ruby threads stay green: each runs on a
  # fiber of its own (kernel/os/posix/gvl.rb has native threads).

  #: () -> value
  def zr_threads_native_m
    Machine.value(QFALSE)
  end

  # The scheduler's switch is a fiber switch.
  #: (value, value, bool) -> bool
  def zr_native_switch(cur, to, exiting)
    false
  end

  # No root fiber has a thread state.
  #: (ptr) -> void
  def zr_thread_state_free(ts)
  end

  # No thread runs C without the GVL, so none comes back from it.
  #: () -> value
  def zr_gvl_returned
    Machine.value(QNIL)
  end

  #: () -> value
  def zr_gvl_wake_fd
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_gvl_release_idle(exiting)
    Machine.value(QFALSE)
  end

  #: (value) -> value
  def zr_region_unblock(root)
    Machine.value(QNIL)
  end

  # The scheduler sleeps until the first deadline.
  #: (value) -> value
  def zr_idle_sleep(ns)
    zr_nanosleep(ns)
  end

  #: () -> bool
  def zr_threads_native
    false
  end

  #: () -> ptr
  def zr_region_self
    Machine.ptr(0)
  end

  # No region: the call runs with the GVL.
  #: (ptr, ptr, ptr, ptr, ptr) -> bool
  def zr_region_run(fn, data, ubf, ubf_data, out)
    Machine.store64(out, 0, zr_gc_call(fn, data, Machine.ptr(0)))
    true
  end

  #: (ptr, ptr, ptr) -> ptr
  def zr_region_with_gvl(me, fn, data)
    Machine.ptr(0)
  end

  #: (value) -> value
  def zr_thread_spawn(root)
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_thread_native_id(root)
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_thread_pthread(root)
    Machine.value(QNIL)
  end

  #: (value) -> value
  def zr_thread_cancel(root)
    Machine.value(QNIL)
  end

  #: () -> value
  def zr_gvl_after_fork
    Machine.value(QNIL)
  end
end
