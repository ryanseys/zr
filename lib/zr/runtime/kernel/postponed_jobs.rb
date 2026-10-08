module Zr::Kern
  # Postponed jobs (ruby/debug.h): C functions that a C extension asks to
  # run at the next safe point, often from a signal handler, where no
  # Ruby can run (stackprof's sampler). A job has a slot in a table of
  # POSTPONED_JOBS; a trigger marks its slot with one store, so a signal
  # that arrives while the jobs run loses none, and a job triggered twice
  # before it runs runs once, as ruby's does. The C entries are in
  # kernel/capi/profile.rb.
  POSTPONED_JOBS = 32

  #: () -> ptr
  def zr_postponed_funcs
    Machine.static(:postponed_funcs, POSTPONED_JOBS * 8)
  end

  #: () -> ptr
  def zr_postponed_data
    Machine.static(:postponed_data, POSTPONED_JOBS * 8)
  end

  #: () -> ptr
  def zr_postponed_marks
    Machine.static(:postponed_marks, POSTPONED_JOBS * 8)
  end

  # Marks job `h` and asks for a safe point. A signal handler may call
  # it: it only stores.
  #: (word) -> void
  def zr_postponed_trigger(h)
    Machine.store64(zr_postponed_marks() + (h * 8), 0, 1)
    Machine.store64(Machine.static(:postponed_pending, 8), 0, 1)
    Machine.store64(Machine.static(:preempt_count, 8), 0, 1)
    zr_poll_set()
  end

  # Runs each marked job, the last slot first, as ruby does: undef when
  # one raised, and the jobs after it wait for the next safe point.
  #: () -> value
  def zr_postponed_run
    pending = Machine.static(:postponed_pending, 8)
    if Machine.load64(pending, 0) == 0
      return Machine.value(QNIL)
    end
    Machine.store64(pending, 0, 0)
    argv = Machine.slot(64)
    i = POSTPONED_JOBS - 1
    while i >= 0
      mark = zr_postponed_marks() + (i * 8)
      if Machine.load64(mark, 0) != 0
        Machine.store64(mark, 0, 0)
        Machine.store64(argv, 0, Machine.load64(zr_postponed_data() + (i * 8), 0))
        if !zr_call_c_returned(Machine.ptr(Machine.load64(zr_postponed_funcs() + (i * 8), 0)), argv, 1)
          Machine.store64(pending, 0, 1)
          return Machine.value(QUNDEF)
        end
      end
      i -= 1
    end
    Machine.value(QNIL)
  end
end
