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
end
