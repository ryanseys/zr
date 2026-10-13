module Zr::Kern
  # The C API's signals, child processes and ends of the program. Each
  # function passes the call on to the core's Process, Signal, Kernel or
  # Thread, which ruby's own C functions back in the same way. A function
  # that fails as a system call does returns -1 with errno set, and
  # raises nothing.

  #: () -> value
  def zr_capi_process
    zr_core_class(Machine.id(:Process))
  end

  # rb_f_kill: `Process.kill(*argv)`, the count of processes signalled.
  #: (i32, ptr) -> value
  def rb_f_kill(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_capi_process(), Machine.id(:kill), Machine.sword(argc), argv))
  end

  # ruby_signal_name: the name of `signo` without SIG ("INT"), or NULL
  # for a number with no name. The core keeps each name for good, so the
  # pointer stays valid.
  #: (i32) -> ptr
  def ruby_signal_name(signo)
    Machine.gates_enter
    zr_c_entered()
    name = zr_capi_call1(zr_core_class(Machine.id(:Signal)), Machine.id(:c_name), zr_fix(Machine.sword(signo)))
    if name == QNIL
      return Machine.ptr(0)
    end
    RString[name].ptr
  end

  # ruby_default_signal: the system's own handling of `sig` in place,
  # then the signal itself, as for a process that does not handle it. A
  # signal whose default ends the process ends it here; one whose
  # default is to ignore it returns.
  #: (i32) -> void
  def ruby_default_signal(sig)
    Machine.gates_enter
    zr_c_entered()
    old = Machine.slot(16)
    zr_os_sigaction(sig, SIGNAL_DEFAULT, old)
    Libc.raise(sig)
  end

  # rb_thread_interrupted: 1 when the thread `th` has an interrupt
  # waiting (Thread#raise, Thread#kill, or a signal for the main thread),
  # else 0.
  #: (value) -> i32
  def rb_thread_interrupted(th)
    Machine.gates_enter
    zr_c_entered()
    r = zr_capi_call1(zr_capi_thread_class(), Machine.id(:interrupted?), th)
    r == QFALSE || r == QNIL ? Machine.i32(0) : Machine.i32(1)
  end

  # rb_interrupt: raises Interrupt with an empty message, as
  # `rb_exc_new(rb_eInterrupt, 0, 0)` makes it.
  #: () -> void
  def rb_interrupt
    Machine.gates_enter
    zr_c_entered()
    exc = zr_c_result(zr_exc_new_str(zr_core_class(Machine.id(:Interrupt)), zr_str_new(Machine.bytes(""), 0)))
    zr_c_result(zr_raise(exc))
  end

  # rb_exit: SystemExit with `status` and the message "exit" goes up
  # through the frames, as `exit(status)` raises it.
  #: (i32) -> void
  def rb_exit(status)
    Machine.gates_enter
    zr_c_entered()
    message = zr_str_new(Machine.bytes("exit"), 4)
    argv = Machine.slot(16)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.sword(status))))
    Machine.store64(argv, 8, Machine.word(message))
    exc = zr_c_result(zr_send(zr_core_class(Machine.id(:SystemExit)), Machine.id(:new), 2, argv))
    zr_c_result(zr_raise(exc))
  end

  # rb_f_exit and rb_f_abort: `exit(*argv)` and `abort(*argv)`.
  #: (i32, ptr) -> value
  def rb_f_exit(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:exit), Machine.sword(argc), argv))
  end

  #: (i32, ptr) -> value
  def rb_f_abort(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_global(G_KERNEL), Machine.id(:abort), Machine.sword(argc), argv))
  end

  # rb_exc_fatal: ends the program with `exc` as rb_fatal does.
  #: (value) -> void
  def rb_exc_fatal(exc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_fatal(exc)
  end

  # The unwind of rb_fatal and rb_exc_fatal (TAG_FATAL). No rescue stops
  # it, and each ensure clause runs; after an ensure that the program
  # wrote it goes on as a raise (zr_ensure_take). At the top of the main
  # thread the exit handlers run, the error is reported, and the status
  # is 1. Another thread ends with the error, and the main thread gets
  # it (Thread#body).
  #: (value) -> void
  def zr_capi_fatal(exc)
    # The error gets its backtrace and cause as a raise gives them
    # (rb_longjmp's setup_exception), then the unwind turns fatal.
    zr_raise(exc)
    Task[zr_task()].pending_kind = PENDING_FATAL
    zr_c_unwind()
  end

  # rb_last_status_set: `$?` becomes the status of the child `pid` with
  # the wait status word `status`.
  #: (i32, i32) -> void
  def rb_last_status_set(status, pid)
    Machine.gates_enter
    zr_c_entered()
    argv = Machine.slot(16)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.sword(status))))
    Machine.store64(argv, 8, Machine.word(zr_fix(Machine.sword(pid))))
    zr_c_result(zr_send(zr_capi_process(), Machine.id(:last_status_set), 2, argv))
  end

  # rb_last_status_get: `$?`, or nil.
  #: () -> value
  def rb_last_status_get
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_capi_process(), Machine.id(:status))
  end

  # rb_waitpid: waits for the child `pid` as waitpid(2) does with `flags`,
  # and returns its pid, with its wait status word at `st` (when not
  # NULL) and `$?` set to its status. A WNOHANG child that still runs
  # gives 0 and leaves `st` alone. A failure gives -1 with errno set, 0
  # at `st`, and `$?` as it was.
  #: (i32, ptr, i32) -> i32
  def rb_waitpid(pid, st, flags)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_waitpid(pid, st, flags)
  end

  # rb_syswait: rb_waitpid for `pid`, with no status word.
  #: (i32) -> void
  def rb_syswait(pid)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_waitpid(pid, Machine.ptr(0), Machine.i32(0))
  end

  #: (i32, ptr, i32) -> i32
  def zr_capi_waitpid(pid, st, flags)
    argv = Machine.slot(16)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.sword(pid))))
    Machine.store64(argv, 8, Machine.word(zr_fix(Machine.sword(flags))))
    r = zr_c_result(zr_send(zr_capi_process(), Machine.id(:c_waitpid), 2, argv))
    if zr_fixnum_p(r)
      if st != 0
        Machine.store32(st, 0, Machine.i32(0))
      end
      Machine.store32(zr_os_errno_ptr(), 0, Machine.i32(0 - zr_fix2long(r)))
      return Machine.i32(-1)
    end
    child = zr_fix2long(zr_ary_at(r, 0))
    if child != 0 && st != 0
      Machine.store32(st, 0, Machine.i32(zr_fix2long(zr_ary_at(r, 1))))
    end
    Machine.i32(child)
  end

  # rb_detach_process: `Process.detach(pid)`, the thread that waits for
  # the child.
  #: (i32) -> value
  def rb_detach_process(pid)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_capi_process(), Machine.id(:detach), zr_fix(Machine.sword(pid)))
  end

  # rb_spawn: starts the command that `argv` gives, as Process.spawn
  # reads its arguments, and returns its pid. A command that does not
  # start gives -1 with errno set; a bad argument raises.
  #: (i32, ptr) -> i32
  def rb_spawn(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_spawn(argc, argv, Machine.ptr(0), 0)
  end

  # rb_spawn_err: the same, and on a failure `errmsg` gets the step that
  # failed in the child ("chdir"), or an empty string, cut to `buflen`.
  #: (i32, ptr, ptr, word) -> i32
  def rb_spawn_err(argc, argv, errmsg, buflen)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_spawn(argc, argv, errmsg, buflen)
  end

  #: (i32, ptr, ptr, word) -> i32
  def zr_capi_spawn(argc, argv, errmsg, buflen)
    n = Machine.sword(argc)
    args = zr_ary_new(n)
    i = 0
    while i < n
      zr_ary_push(args, Machine.value(Machine.load64(argv + (i * 8), 0)))
      i += 1
    end
    r = zr_capi_call1(zr_capi_process(), Machine.id(:c_spawn), args)
    pid = zr_fix2long(zr_ary_at(r, 0))
    if pid >= 0
      return Machine.i32(pid)
    end
    step = zr_ary_at(r, 1)
    # The child names only a step that failed before its exec; for the
    # command itself `errmsg` stays as C gave it.
    if errmsg != 0 && buflen > 0 && RString[step].len > 0
      len = RString[step].len
      if len > buflen - 1
        len = buflen - 1
      end
      zr_memcpy(errmsg, RString[step].ptr, len)
      Machine.store8(errmsg + len, 0, Machine.i8(0))
    end
    Machine.store32(zr_os_errno_ptr(), 0, Machine.i32(0 - pid))
    Machine.i32(-1)
  end

  # rb_f_exec: `exec(*argv)`. It returns only by an error, which goes up.
  #: (i32, ptr) -> value
  def rb_f_exec(argc, argv)
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_capi_process(), Machine.id(:exec), Machine.sword(argc), argv))
  end

  # rb_proc_exec: the process becomes `/bin/sh -c cmd`. Only a failure
  # returns: -1, with errno set.
  #: (ptr) -> i32
  def rb_proc_exec(cmd)
    Machine.gates_enter
    zr_c_entered()
    r = zr_capi_call1(zr_capi_process(), Machine.id(:c_exec_shell), zr_str_new(cmd, zr_cstr_len(cmd)))
    Machine.store32(zr_os_errno_ptr(), 0, Machine.i32(zr_fix2long(r)))
    Machine.i32(-1)
  end

  # rb_proc_times: `Process.times`.
  #: (value) -> value
  def rb_proc_times(obj)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_capi_process(), Machine.id(:times))
  end

  # rb_thread_atfork: what a child of C's own fork(2) needs before it runs
  # Ruby: a new random seed, and only the thread that forked.
  #: () -> void
  def rb_thread_atfork
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_capi_process(), Machine.id(:thread_atfork))
  end

  # rb_thread_atfork_before_exec: the same for a child that only calls
  # exec next: only the thread that forked lives on.
  #: () -> void
  def rb_thread_atfork_before_exec
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_capi_thread_class(), Machine.id(:after_fork))
  end

  # rb_process_status_wait: `Process::Status.wait(pid, flags)`, which a
  # fiber scheduler (io-event) calls: the child's status, nil while a
  # WNOHANG child runs, or a status of pid -1 when there is no child.
  #: (i32, i32) -> value
  def rb_process_status_wait(pid, flags)
    Machine.gates_enter
    zr_c_entered()
    e = zr_const_row_in(zr_core_class(Machine.id(:Process)), Machine.id(:Status), false)
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.sword(pid))))
    Machine.store64(argv, 8, Machine.word(zr_fix(Machine.sword(flags))))
    zr_c_result(zr_trace_point_send(CEntry[e].value, Machine.id(:wait), 2, argv))
  end

  # rb_process_status_for: a frozen status of the child `pid` with the
  # wait status word `status`, which a fiber scheduler made. zr's status
  # keeps no errno.
  #: (i32, i32, i32) -> value
  def rb_process_status_for(pid, status, error)
    Machine.gates_enter
    zr_c_entered()
    e = zr_const_row_in(zr_core_class(Machine.id(:Process)), Machine.id(:Status), false)
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.sword(pid))))
    Machine.store64(argv, 8, Machine.word(zr_fix(Machine.sword(status))))
    zr_c_result(zr_send(CEntry[e].value, Machine.id(:made), 2, argv))
  end
end
