module Zr::Kern
  # The thread event hooks that C adds (rb_internal_thread_add_event_hook,
  # capi/thread.rb), newest first. The scheduler (core/thread.rb) tells
  # each change of a thread's state here: a thread started, is ready to
  # run, runs, stops running, or ended. Each hook whose events include it
  # gets `callback(event, &{thread}, data)`.
  class ThreadHook < Layout
    attr_accessor :next #: ptr
    attr_accessor :callback #: ptr
    attr_accessor :events #: word
    attr_accessor :data #: word
  end

  # The word that holds the first hook.
  #: () -> ptr
  def zr_thread_hooks
    Machine.static(:thread_hooks, 8)
  end

  # Tells the hooks that `thread` had `event` (an Integer). With no hook,
  # as in a program with no C, it costs a load.
  #: (value, value) -> value
  def zr_thread_event(event, thread)
    hook = Machine.ptr(Machine.load64(zr_thread_hooks(), 0))
    if hook == 0
      return Machine.value(QNIL)
    end
    bit = zr_fix2long(event)
    # rb_internal_thread_event_data_t: the thread.
    info = Machine.slot(8)
    Machine.store64(info, 0, Machine.word(thread))
    argv = Machine.slot(64)
    while hook != 0
      after = ThreadHook[hook].next
      if (ThreadHook[hook].events & bit) != 0
        Machine.store64(argv, 0, bit)
        Machine.store64(argv, 8, Machine.word(info))
        Machine.store64(argv, 16, ThreadHook[hook].data)
        zr_call_c(ThreadHook[hook].callback, argv, 3)
      end
      hook = after
    end
    Machine.value(QNIL)
  end
end
